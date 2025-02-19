{{- define "socialnetwork.templates.redis.redis.conf"  }}
io-threads 16
io-threads-do-reads yes
port 6379
tls-port 0

# Security (Only enable TLS if needed)
tls-cert-file /keys/server.crt
tls-key-file /keys/server.key
tls-auth-clients no

# Increase max clients (Prevent connection limit errors)
maxclients 50000

# Optimize memory usage (Evict least-used keys first)
maxmemory-policy allkeys-lru

# Enable AOF persistence (Prevents data loss)
appendonly yes
appendfsync everysec

# Improve network performance
tcp-backlog 65535
tcp-keepalive 300
{{- end }}
