---- Licensed to the Apache Software Foundation (ASF) under one
-- or more contributor license agreements. See the NOTICE file
-- distributed with this work for additional information
-- regarding copyright ownership. The ASF licenses this file
-- to you under the Apache License, Version 2.0 (the
-- "License"); you may not use this file except in compliance
-- with the License. You may obtain a copy of the License at
--
--   http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing,
-- software distributed under the License is distributed on an
-- "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
-- KIND, either express or implied. See the License for the
-- specific language governing permissions and limitations
-- under the License.

local TTransport = require 'TTransport'
local TTransportException = TTransport.TTransportException
local TTransportBase = TTransport.TTransportBase
local Thrift = require 'Thrift'
local ttype = Thrift.ttype
local terror = Thrift.terror

-- Use NGINX logging
local ngx = require "ngx"  -- Ensure ngx module is loaded
local ngx_log = ngx.log
local ngx_ERR = ngx.ERR
local ngx_WARN = ngx.WARN
local ngx_INFO = ngx.INFO
local ngx_DEBUG = ngx.DEBUG

-- TSocketBase
local TSocketBase = TTransportBase:new{
  __type = 'TSocketBase',
  timeout = 1000000,  -- Default timeout (5 minutes)
  host = 'localhost',
  port = 9090,
  handle = nil
}

function TSocketBase:close()
  if self.handle then
    ngx_log(ngx_INFO, "[TSocket] Closing socket connection to " .. self.host .. ":" .. self.port)
    self.handle:close()
    self.handle = nil
  else
    ngx_log(ngx_WARN, "[TSocket] Close called, but handle is nil")
  end
end

function TSocketBase:setKeepAlive(timeout, size)
  if self.handle then
    ngx_log(ngx_DEBUG, "[TSocket] Setting keep-alive: timeout=" .. tostring(timeout) .. ", size=" .. tostring(size))
    self.handle:setkeepalive(timeout, size)
  else
    ngx_log(ngx_ERR, "[TSocket] Attempted to set keep-alive but handle is nil")
  end
end

-- Returns a table with the fields host and port
function TSocketBase:getSocketInfo()
  if self.handle then
    return self.handle:getsockinfo()
  end
  ngx_log(ngx_ERR, "[TSocket] Attempted to get socket info but handle is nil")
  terror(TTransportException:new{errorCode = TTransportException.NOT_OPEN})
end

function TSocketBase:setTimeout(timeout)
  if timeout and type(timeout) == 'number' then
    if self.handle then
      ngx_log(ngx_INFO, "[TSocket] Setting timeout to " .. tostring(timeout) .. " ms")
      self.handle:settimeout(timeout)
    else
      ngx_log(ngx_WARN, "[TSocket] Timeout set but handle is nil")
    end
    self.timeout = timeout
  else
    ngx_log(ngx_ERR, "[TSocket] Invalid timeout value: " .. tostring(timeout))
  end
end

-- TSocket
local TSocket = TSocketBase:new{
  __type = 'TSocket',
  host = 'localhost',
  port = 9090
}

function TSocket:isOpen()
  return self.handle ~= nil
end

function TSocket:open()
  if not self.handle then
    ngx_log(ngx.INFO, "[TSocket] FINAL TIMEOUT before socket open: " .. tostring(self.timeout))

    ngx_log(ngx_INFO, "[TSocket] Opening socket to " .. self.host .. ":" .. self.port .. " with timeout=" .. self.timeout)
    -- Use NGINX socket instead of the built-in lua socket
    self.handle = ngx.socket.tcp()
    self.handle:settimeout(self.timeout)
  end

  local ok, err = self.handle:connect(self.host, self.port)
  if not ok then
    ngx_log(ngx_ERR, "[TSocket] Connection failed to " .. self.host .. ":" .. self.port .. " (" .. tostring(err) .. ")")
    terror(TTransportException:new{
      message = 'Could not connect to ' .. self.host .. ':' .. self.port
        .. ' (' .. tostring(err) .. ')'
    })
  else
    ngx_log(ngx_INFO, "[TSocket] Successfully connected to " .. self.host .. ":" .. self.port)
  end
end

function TSocket:read(len)
  ngx_log(ngx_DEBUG, "[TSocket] Attempting to read " .. tostring(len) .. " bytes from " .. self.host .. ":" .. self.port)
  local buf, err = self.handle:receive(len)
  if not buf or string.len(buf) ~= len then
    ngx_log(ngx_ERR, "[TSocket] Read error on " .. self.host .. ":" .. self.port .. ": " .. tostring(err))
    terror(TTransportException:new{errorCode = TTransportException.UNKNOWN})
  end
  ngx_log(ngx_DEBUG, "[TSocket] Read successful")
  return buf
end

function TSocket:write(buf)
  ngx_log(ngx_DEBUG, "[TSocket] Writing " .. tostring(#buf) .. " bytes to " .. self.host .. ":" .. self.port)
  local ok, err = self.handle:send(buf)
  if not ok then
    ngx_log(ngx_ERR, "[TSocket] Write error on " .. self.host .. ":" .. self.port .. ": " .. tostring(err))
  end
end

function TSocket:flush()
  ngx_log(ngx_DEBUG, "[TSocket] Flushing data")
end

-- TServerSocket
local TServerSocket = TSocketBase:new{
  __type = 'TServerSocket',
  host = 'localhost',
  port = 9090
}

function TServerSocket:listen()
  if self.handle then
    self:close()
  end

  local sock, err = ngx.socket.tcp()
  if sock then
    ngx_log(ngx_INFO, "[TServerSocket] Listening on " .. self.host .. ":" .. self.port)
    self.handle = sock
    self.handle:settimeout(self.timeout)
    self.handle:listen()
  else
    ngx_log(ngx_ERR, "[TServerSocket] Failed to listen: " .. tostring(err))
    terror(err)
  end
end

function TServerSocket:accept()
  local client, err = self.handle:accept()
  if err then
    ngx_log(ngx_ERR, "[TServerSocket] Accept error: " .. tostring(err))
    terror(err)
  end
  ngx_log(ngx_INFO, "[TServerSocket] Accepted new client connection")
  return TSocket:new({handle = client})
end

return TSocket
