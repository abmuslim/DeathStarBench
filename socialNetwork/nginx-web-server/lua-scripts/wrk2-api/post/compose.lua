local _M = {}
local k8s_suffix = os.getenv("fqdn_suffix")
if (k8s_suffix == nil) then
  k8s_suffix = ""
end

local function _StrIsEmpty(s)
  return s == nil or s == ''
end

function _M.ComposePost()
  local bridge_tracer = require "opentracing_bridge_tracer"
  local ngx = ngx
  local cjson = require "cjson"

  local GenericObjectPool = require "GenericObjectPool"
  local social_network_ComposePostService = require "social_network_ComposePostService"
  local ComposePostServiceClient = social_network_ComposePostService.ComposePostServiceClient

  GenericObjectPool:setMaxTotal(30000)
  GenericObjectPool:setmaxIdleTime(15000)

  ngx.req.read_body()
  local post = ngx.req.get_post_args()

  if (_StrIsEmpty(post.user_id) or _StrIsEmpty(post.username) or
      _StrIsEmpty(post.post_type) or _StrIsEmpty(post.text)) then
    ngx.status = ngx.HTTP_BAD_REQUEST
    ngx.say("Incomplete arguments")
    ngx.log(ngx.ERR, "Incomplete arguments")
    ngx.exit(ngx.HTTP_BAD_REQUEST)
  end

  local req_id = tonumber(string.sub(ngx.var.request_id, 0, 15), 16)
  ngx.log(ngx.INFO, "[ComposePost] Incoming request with req_id: ", req_id)

  local tracer = bridge_tracer.new_from_global()
  local parent_span_context = tracer:binary_extract(ngx.var.opentracing_binary_context)

  local t1 = ngx.now()

  local client
  local status, ret

  -- Connect to ComposePostService
  ngx.log(ngx.INFO, "[ComposePost] Getting connection to compose-post-service on port 9090")
  client = GenericObjectPool:connection(
    ComposePostServiceClient,
    "compose-post-service" .. k8s_suffix,
    9090
  )

  local span = tracer:start_span("compose_post_client",
      { ["references"] = { { "child_of", parent_span_context } } })
  local carrier = {}
  tracer:text_map_inject(span:context(), carrier)

  if (not _StrIsEmpty(post.media_ids) and not _StrIsEmpty(post.media_types)) then
    status, ret = pcall(client.ComposePost, client,
        req_id, post.username, tonumber(post.user_id), post.text,
        cjson.decode(post.media_ids), cjson.decode(post.media_types),
        tonumber(post.post_type), carrier)
  else
    status, ret = pcall(client.ComposePost, client,
        req_id, post.username, tonumber(post.user_id), post.text,
        {}, {}, tonumber(post.post_type), carrier)
  end

  if not status then
    ngx.status = ngx.HTTP_INTERNAL_SERVER_ERROR
    if (ret.message) then
      ngx.say("compost_post failure: " .. ret.message)
      ngx.log(ngx.ERR, "compost_post failure: " .. ret.message)
    else
      ngx.say("compost_post failure: " .. ret)
      ngx.log(ngx.ERR, "compost_post failure: " .. ret)
    end
    if client and client.iprot and client.iprot.trans then
      client.iprot.trans:close()
    end
    ngx.exit(ngx.status)
  end

  -- Return connection to pool safely
  local ok, err = pcall(GenericObjectPool.returnConnection, GenericObjectPool, client)
  if not ok then
    ngx.log(ngx.ERR, "Error returning connection to pool: ", err)
  end

  local t2 = ngx.now()
  ngx.log(ngx.INFO, "[ComposePost] Compose request took " .. ((t2 - t1) * 1000) .. " ms")

  ngx.status = ngx.HTTP_OK
  ngx.say("Successfully upload post")
  span:finish()
  ngx.exit(ngx.status)
end

return _M

