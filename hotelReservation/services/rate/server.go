package rate

import (
	"context"
	"encoding/json"
	"fmt"
	"net"
	"sort"
	"strings"
	"sync"
	"time"

    
	"github.com/bradfitz/gomemcache/memcache"
	"github.com/delimitrou/DeathStarBench/tree/master/hotelReservation/registry"
	pb "github.com/delimitrou/DeathStarBench/tree/master/hotelReservation/services/rate/proto"
	"github.com/delimitrou/DeathStarBench/tree/master/hotelReservation/tls"
	"github.com/google/uuid"
	"github.com/grpc-ecosystem/grpc-opentracing/go/otgrpc"
	"github.com/opentracing/opentracing-go"
	"github.com/rs/zerolog/log"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo"
	"google.golang.org/grpc"
	"google.golang.org/grpc/keepalive"

	"google.golang.org/grpc/status"
    "google.golang.org/grpc/codes"
)

const name = "srv-rate"

// Server implements the rate service
type Server struct {
	pb.UnimplementedRateServer

	uuid string

	Tracer      opentracing.Tracer
	Port        int
	IpAddr      string
	MongoClient *mongo.Client
	Registry    *registry.Client
	MemcClient  *memcache.Client
}

// Run starts the server
func (s *Server) Run() error {
	opentracing.SetGlobalTracer(s.Tracer)

	if s.Port == 0 {
		return fmt.Errorf("server port must be set")
	}

	s.uuid = uuid.New().String()

	opts := []grpc.ServerOption{
		grpc.KeepaliveParams(keepalive.ServerParameters{
			Timeout: 120 * time.Second,
		}),
		grpc.KeepaliveEnforcementPolicy(keepalive.EnforcementPolicy{
			PermitWithoutStream: true,
		}),
		grpc.UnaryInterceptor(
			otgrpc.OpenTracingServerInterceptor(s.Tracer),
		),
	}

	if tlsopt := tls.GetServerOpt(); tlsopt != nil {
		opts = append(opts, tlsopt)
	}

	srv := grpc.NewServer(opts...)

	pb.RegisterRateServer(srv, s)

	lis, err := net.Listen("tcp", fmt.Sprintf(":%d", s.Port))
	if err != nil {
		log.Fatal().Msgf("failed to listen: %v", err)
	}

	err = s.Registry.Register(name, s.uuid, s.IpAddr, s.Port)
	if err != nil {
		return fmt.Errorf("failed register: %v", err)
	}
	log.Info().Msg("Successfully registered in consul")

	return srv.Serve(lis)
}

// Shutdown cleans up any processes
func (s *Server) Shutdown() {
	s.Registry.Deregister(s.uuid)
}

// GetRates gets rates for hotels for specific date range.
func (s *Server) GetRates(ctx context.Context, req *pb.Request) (*pb.Result, error) {
	res := new(pb.Result)

    ratePlans := make(RatePlans, 0)

    hotelIds := []string{}
    rateMap := make(map[string]struct{})
    for _, hotelID := range req.HotelIds {
        if isValidHotelID(hotelID) {
            hotelIds = append(hotelIds, hotelID)
            rateMap[hotelID] = struct{}{}
        } else {
            log.Warn().Msgf("Received invalid hotel ID: %s", hotelID)
            // Optionally, you can return an error response
            return nil, status.Errorf(codes.InvalidArgument, "Invalid hotel ID: %s", hotelID)
        }
    }

	// first check memcached(get-multi)
	memSpan, _ := opentracing.StartSpanFromContext(ctx, "memcached_get_multi_rate")
	memSpan.SetTag("span.kind", "client")

	resMap, err := s.MemcClient.GetMulti(hotelIds)
	memSpan.Finish()

	var wg sync.WaitGroup
	var mutex sync.Mutex
	if err != nil && err != memcache.ErrCacheMiss {
    log.Error().Msgf("Memcached error while trying to get hotel [id: %v]: %s", hotelIds, err)
    return nil, status.Errorf(codes.Unavailable, "Unable to retrieve data from cache")
	} else {
		for hotelId, item := range resMap {
			rateStrs := strings.Split(string(item.Value), "\n")
			log.Trace().Msgf("memc hit, hotelId = %s,rate strings: %v", hotelId, rateStrs)

			for _, rateStr := range rateStrs {
				if len(rateStr) != 0 {
					rateP := new(pb.RatePlan)
					json.Unmarshal([]byte(rateStr), rateP)
					ratePlans = append(ratePlans, rateP)
				}
			}

			delete(rateMap, hotelId)
		}

		wg.Add(len(rateMap))
		for hotelId := range rateMap {
			go func(id string) {
				defer wg.Done()
				log.Trace().Msgf("memc miss, hotelId = %s", id)
				log.Trace().Msg("memcached miss, set up mongo connection")
			
				mongoSpan, _ := opentracing.StartSpanFromContext(ctx, "mongo_rate")
				mongoSpan.SetTag("span.kind", "client")
			
				collection := s.MongoClient.Database("rate-db").Collection("inventory")
				filter := bson.D{{"hotelId", id}}
				curr, err := collection.Find(context.TODO(), filter)
				if err != nil {
					log.Error().Msgf("Failed to get rate data for hotelId [%v]: %v", id, err)
					mongoSpan.Finish()
					return
				}
			
				tmpRatePlans := make(RatePlans, 0)
				err = curr.All(context.TODO(), &tmpRatePlans)
				if err != nil {
					log.Error().Msgf("Failed to process rate data for hotelId [%v]: %v", id, err)
					mongoSpan.Finish()
					return
				}
			
				mongoSpan.Finish()
			
				memcStr := ""
				for _, r := range tmpRatePlans {
					mutex.Lock()
					ratePlans = append(ratePlans, r)
					mutex.Unlock()
					rateJson, err := json.Marshal(r)
					if err != nil {
						log.Error().Msgf("Failed to marshal plan [Code: %v] with error: %v", r.Code, err)
						continue
					}
					memcStr += string(rateJson) + "\n"
				}
				s.MemcClient.Set(&memcache.Item{Key: id, Value: []byte(memcStr)})
			}(hotelId)
			
		}
	}
	wg.Wait()

	sort.Sort(ratePlans)
	res.RatePlans = ratePlans

	return res, nil
}

type RatePlans []*pb.RatePlan

func (r RatePlans) Len() int {
	return len(r)
}

func (r RatePlans) Swap(i, j int) {
	r[i], r[j] = r[j], r[i]
}

func (r RatePlans) Less(i, j int) bool {
	return r[i].RoomType.TotalRate > r[j].RoomType.TotalRate
}

// isValidHotelID checks if the hotel ID is a valid numeric string.
func isValidHotelID(hotelID string) bool {
    for _, c := range hotelID {
        if c < '0' || c > '9' {
            return false
        }
    }
    return true
}