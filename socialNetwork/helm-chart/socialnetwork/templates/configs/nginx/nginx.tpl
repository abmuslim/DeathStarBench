{{- define "socialnetwork.templates.nginx.nginx.conf" }}
# Load the OpenTracing dynamic module.
load_module modules/ngx_http_opentracing_module.so;

worker_processes auto;
error_log logs/error.log;

events {
  use epoll;
  worker_connections 200000;
  multi_accept on;
}

env fqdn_suffix;

http {
  # Load tracer
  opentracing on;
  opentracing_load_tracer /usr/local/lib/libjaegertracing_plugin.so /usr/local/openresty/nginx/jaeger-config.json;

  include mime.types;
  default_type application/octet-stream;

  client_header_timeout 3000s;
  client_body_timeout 3000s;
  proxy_read_timeout 3000s;
  proxy_connect_timeout 3000s;
  proxy_send_timeout 3000s;

  # ✅ Custom log format with request time
  log_format latency_log '$remote_addr - $remote_user [$time_local] '
                         '"$request" $status $body_bytes_sent '
                         '"$http_referer" "$http_user_agent" '
                         'rt=$request_time uri=$request_uri';

  # ✅ Enable access logging
  access_log /var/log/nginx/access.log latency_log;
  
  open_file_cache max=100000 inactive=20s;
  open_file_cache_valid 30s;
  open_file_cache_errors off;

  sendfile on;
  tcp_nopush on;
  tcp_nodelay on;

  keepalive_timeout 3000s;
  keepalive_requests 1000000;

  resolver {{ .Values.global.nginx.resolverName }} valid=10s ipv6=off;

  lua_package_path '/usr/local/openresty/nginx/lua-scripts/?.lua;/usr/local/openresty/luajit/share/lua/5.1/?.lua;;';
  lua_shared_dict config 10m;

  init_by_lua_block {
    local bridge_tracer = require "opentracing_bridge_tracer"
    local GenericObjectPool = require "GenericObjectPool"
    local ngx = ngx
    local jwt = require "resty.jwt"
    local cjson = require 'cjson'

    local social_network_UserTimelineService = require 'social_network_UserTimelineService'
    local UserTimelineServiceClient = social_network_UserTimelineService.social_network_UserTimelineService
    local social_network_SocialGraphService = require 'social_network_SocialGraphService'
    local SocialGraphServiceClient = social_network_SocialGraphService.SocialGraphServiceClient
    local social_network_ComposePostService = require 'social_network_ComposePostService'
    local ComposePostServiceClient = social_network_ComposePostService.ComposePostServiceClient
    local social_network_UserService = require 'social_network_UserService'
    local UserServiceClient = social_network_UserService.UserServiceClient

    local config = ngx.shared.config;
    config:set("secret", "secret")
    config:set("cookie_ttl", 3600 * 24)
    config:set("ssl", false)
  }

  server {
    listen 8080 reuseport;
    server_name localhost;

    lua_need_request_body on;

    lua_ssl_trusted_certificate /keys/CA.pem;
    lua_ssl_ciphers ALL:!ADH:!LOW:!EXP:!MD5:@STRENGTH;

    access_log /var/log/nginx/access.log latency_log;
    

    # Checklist: Make sure that the location here is consistent
    # with the location you specified in wrk2.
    location /api/user/register {
          if ($request_method = 'OPTIONS') {
            add_header 'Access-Control-Allow-Origin' '*';
            add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS';
            add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range';
            add_header 'Access-Control-Max-Age' 1728000;
            add_header 'Content-Type' 'text/plain; charset=utf-8';
            add_header 'Content-Length' 0;
            return 204;
          }
          if ($request_method = 'POST') {
            add_header 'Access-Control-Allow-Origin' '*';
            add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS';
            add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range';
            add_header 'Access-Control-Expose-Headers' 'Content-Length,Content-Range';
          }
          if ($request_method = 'GET') {
            add_header 'Access-Control-Allow-Origin' '*';
            add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS';
            add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range';
            add_header 'Access-Control-Expose-Headers' 'Content-Length,Content-Range';
          }
      content_by_lua '
          local client = require "api/user/register"
          client.RegisterUser();
      ';
    }

    location /api/user/follow {
          if ($request_method = 'OPTIONS') {
            add_header 'Access-Control-Allow-Origin' '*';
            add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS';
            add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range';
            add_header 'Access-Control-Max-Age' 1728000;
            add_header 'Content-Type' 'text/plain; charset=utf-8';
            add_header 'Content-Length' 0;
            return 204;
          }
          if ($request_method = 'POST') {
            add_header 'Access-Control-Allow-Origin' '*';
            add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS';
            add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range';
            add_header 'Access-Control-Expose-Headers' 'Content-Length,Content-Range';
          }
          if ($request_method = 'GET') {
            add_header 'Access-Control-Allow-Origin' '*';
            add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS';
            add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range';
            add_header 'Access-Control-Expose-Headers' 'Content-Length,Content-Range';
          }
      content_by_lua '
          local client = require "api/user/follow"
          client.Follow();
      ';
    }

    location /api/user/unfollow {
          if ($request_method = 'OPTIONS') {
            add_header 'Access-Control-Allow-Origin' '*';
            add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS';
            add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range';
            add_header 'Access-Control-Max-Age' 1728000;
            add_header 'Content-Type' 'text/plain; charset=utf-8';
            add_header 'Content-Length' 0;
            return 204;
          }
          if ($request_method = 'POST') {
            add_header 'Access-Control-Allow-Origin' '*';
            add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS';
            add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range';
            add_header 'Access-Control-Expose-Headers' 'Content-Length,Content-Range';
          }
          if ($request_method = 'GET') {
            add_header 'Access-Control-Allow-Origin' '*';
            add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS';
            add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range';
            add_header 'Access-Control-Expose-Headers' 'Content-Length,Content-Range';
          }
      content_by_lua '
          local client = require "api/user/unfollow"
          client.Unfollow();
      ';
    }

    location /api/user/login {
          if ($request_method = 'OPTIONS') {
            add_header 'Access-Control-Allow-Origin' '*';
            add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS';
            add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range';
            add_header 'Access-Control-Max-Age' 1728000;
            add_header 'Content-Type' 'text/plain; charset=utf-8';
            add_header 'Content-Length' 0;
            return 204;
          }
          if ($request_method = 'POST') {
            add_header 'Access-Control-Allow-Origin' '*';
            add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS';
            add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range';
            add_header 'Access-Control-Expose-Headers' 'Content-Length,Content-Range';
          }
          if ($request_method = 'GET') {
            add_header 'Access-Control-Allow-Origin' '*';
            add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS';
            add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range';
            add_header 'Access-Control-Expose-Headers' 'Content-Length,Content-Range';
          }
      content_by_lua '
          local client = require "api/user/login"
          client.Login();
      ';
    }

    location /api/post/compose {
          if ($request_method = 'OPTIONS') {
            add_header 'Access-Control-Allow-Origin' '*';
            add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS';
            add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range';
            add_header 'Access-Control-Max-Age' 1728000;
            add_header 'Content-Type' 'text/plain; charset=utf-8';
            add_header 'Content-Length' 0;
            return 204;
          }
          if ($request_method = 'POST') {
            add_header 'Access-Control-Allow-Origin' '*';
            add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS';
            add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range';
            add_header 'Access-Control-Expose-Headers' 'Content-Length,Content-Range';
          }
          if ($request_method = 'GET') {
            add_header 'Access-Control-Allow-Origin' '*';
            add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS';
            add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range';
            add_header 'Access-Control-Expose-Headers' 'Content-Length,Content-Range';
          }
      content_by_lua '
          local client = require "api/post/compose"
          client.ComposePost();
      ';
    }

    location /api/user-timeline/read {
          if ($request_method = 'OPTIONS') {
            add_header 'Access-Control-Allow-Origin' '*';
            add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS';
            add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range';
            add_header 'Access-Control-Max-Age' 1728000;
            add_header 'Content-Type' 'text/plain; charset=utf-8';
            add_header 'Content-Length' 0;
            return 204;
          }
          if ($request_method = 'POST') {
            add_header 'Access-Control-Allow-Origin' '*';
            add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS';
            add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range';
            add_header 'Access-Control-Expose-Headers' 'Content-Length,Content-Range';
          }
          if ($request_method = 'GET') {
            add_header 'Access-Control-Allow-Origin' '*';
            add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS';
            add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range';
            add_header 'Access-Control-Expose-Headers' 'Content-Length,Content-Range';
          }
      content_by_lua '
          local client = require "api/user-timeline/read"
          client.ReadUserTimeline();
      ';
    }

    location /api/home-timeline/read {
            if ($request_method = 'OPTIONS') {
              add_header 'Access-Control-Allow-Origin' '*';
              add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS';
              add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range';
              add_header 'Access-Control-Max-Age' 1728000;
              add_header 'Content-Type' 'text/plain; charset=utf-8';
              add_header 'Content-Length' 0;
              return 204;
            }
            if ($request_method = 'POST') {
              add_header 'Access-Control-Allow-Origin' '*';
              add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS';
              add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range';
              add_header 'Access-Control-Expose-Headers' 'Content-Length,Content-Range';
            }
            if ($request_method = 'GET') {
              add_header 'Access-Control-Allow-Origin' '*';
              add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS';
              add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range';
              add_header 'Access-Control-Expose-Headers' 'Content-Length,Content-Range';
            }
      content_by_lua '
          local client = require "api/home-timeline/read"
          client.ReadHomeTimeline();
      ';
    }

    # # get userinfo lua
    # location /api/user/user_info {
    #       if ($request_method = 'OPTIONS') {
    #         add_header 'Access-Control-Allow-Origin' '*';
    #         add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS';
    #         add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range';
    #         add_header 'Access-Control-Max-Age' 1728000;
    #         add_header 'Content-Type' 'text/plain; charset=utf-8';
    #         add_header 'Content-Length' 0;
    #         return 204;
    #       }
    #       if ($request_method = 'POST') {
    #         add_header 'Access-Control-Allow-Origin' '*';
    #         add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS';
    #         add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range';
    #         add_header 'Access-Control-Expose-Headers' 'Content-Length,Content-Range';
    #       }
    #       if ($request_method = 'GET') {
    #         add_header 'Access-Control-Allow-Origin' '*';
    #         add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS';
    #         add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range';
    #         add_header 'Access-Control-Expose-Headers' 'Content-Length,Content-Range';
    #       }
    #   content_by_lua '
    #       local client = require "api/user/user_info"
    #       client.UserInfo();
    #   ';
    # }
    # get follower lua
    location /api/user/get_follower {
          if ($request_method = 'OPTIONS') {
            add_header 'Access-Control-Allow-Origin' '*';
            add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS';
            add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range';
            add_header 'Access-Control-Max-Age' 1728000;
            add_header 'Content-Type' 'text/plain; charset=utf-8';
            add_header 'Content-Length' 0;
            return 204;
          }
          if ($request_method = 'POST') {
            add_header 'Access-Control-Allow-Origin' '*';
            add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS';
            add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range';
            add_header 'Access-Control-Expose-Headers' 'Content-Length,Content-Range';
          }
          if ($request_method = 'GET') {
            add_header 'Access-Control-Allow-Origin' '*';
            add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS';
            add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range';
            add_header 'Access-Control-Expose-Headers' 'Content-Length,Content-Range';
          }
      content_by_lua '
          local client = require "api/user/get_follower"
          client.GetFollower();
      ';
    }

    # get followee lua
    location /api/user/get_followee {
          if ($request_method = 'OPTIONS') {
            add_header 'Access-Control-Allow-Origin' '*';
            add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS';
            add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range';
            add_header 'Access-Control-Max-Age' 1728000;
            add_header 'Content-Type' 'text/plain; charset=utf-8';
            add_header 'Content-Length' 0;
            return 204;
          }
          if ($request_method = 'POST') {
            add_header 'Access-Control-Allow-Origin' '*';
            add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS';
            add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range';
            add_header 'Access-Control-Expose-Headers' 'Content-Length,Content-Range';
          }
          if ($request_method = 'GET') {
            add_header 'Access-Control-Allow-Origin' '*';
            add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS';
            add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range';
            add_header 'Access-Control-Expose-Headers' 'Content-Length,Content-Range';
          }
      content_by_lua '
          local client = require "api/user/get_followee"
          client.GetFollowee();
      ';
    }
    location / {
      if ($request_method = 'OPTIONS') {
        add_header 'Access-Control-Allow-Origin' '*';
        add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS';
        add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range';
        add_header 'Access-Control-Max-Age' 1728000;
        add_header 'Content-Type' 'text/plain; charset=utf-8';
        add_header 'Content-Length' 0;
        return 204;
      }
      if ($request_method = 'POST') {
        add_header 'Access-Control-Allow-Origin' '*';
        add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS';
        add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range';
        add_header 'Access-Control-Expose-Headers' 'Content-Length,Content-Range';
      }
      if ($request_method = 'GET') {
        add_header 'Access-Control-Allow-Origin' '*';
        add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS';
        add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range';
        add_header 'Access-Control-Expose-Headers' 'Content-Length,Content-Range';
      }
      root pages;
    }

    location /wrk2-api/home-timeline/read {
      content_by_lua '
          local client = require "wrk2-api/home-timeline/read"
          client.ReadHomeTimeline();
      ';
    }

    location /wrk2-api/user-timeline/read {
      content_by_lua '
          local client = require "wrk2-api/user-timeline/read"
          client.ReadUserTimeline();
      ';
    }

    location /wrk2-api/post/compose {
      content_by_lua '
          local client = require "wrk2-api/post/compose"
          client.ComposePost();
      ';
    }

    location /wrk2-api/user/register {
      content_by_lua '
          local client = require "wrk2-api/user/register"
          client.RegisterUser();
      ';
    }

    location /wrk2-api/user/follow {
      content_by_lua '
          local client = require "wrk2-api/user/follow"
          client.Follow();
      ';
    }

    location /wrk2-api/user/unfollow {
      content_by_lua '
          local client = require "wrk2-api/user/unfollow"
          client.Unfollow();
      ';
    }
    
    location /status {
    stub_status;
    allow all;
    }
  }
}
{{- end }}
