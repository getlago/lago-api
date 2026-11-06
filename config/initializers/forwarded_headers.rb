# frozen_string_literal: true

# Under Rack 3, `request.remote_ip`, scheme, host and port prefer the RFC 7239 `Forwarded` header over
# `X-Forwarded-*`. Our proxies set `X-Forwarded-For` but may pass a client-supplied `Forwarded` through,
# which would let a client pick its own IP and get around the per-IP auth limits.
Rack::Request.forwarded_priority = [:x_forwarded]
