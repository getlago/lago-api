# frozen_string_literal: true

module Lago
  # redis-client middleware that retries commands rejected with a LOADING error.
  #
  # Redis replies `LOADING Redis is loading the dataset in memory` while a node
  # warms up after a restart or an ElastiCache failover/upgrade. The socket is
  # healthy, so `reconnect_attempts` does not apply; the command itself has to be
  # retried until the node finishes loading.
  #
  # The retry schedule (backoff intervals in seconds, slept between attempts) is
  # read per-client from redis-client's `custom` config under
  # `:loading_retry_attempts`:
  #
  #   RedisClient.config(
  #     custom: {loading_retry_attempts: [0.1, 0.4, 0.9]},
  #     middlewares: [Lago::RedisLoadingRetryMiddleware]
  #   )
  #
  # `custom` is used (rather than a configured module) because Sidekiq logs the
  # connection options through `Marshal.dump`, which cannot dump an anonymous
  # module but handles a named module and a plain hash. An empty or missing
  # schedule means the LOADING error propagates unchanged.
  module RedisLoadingRetryMiddleware
    LOADING_CODE = "LOADING"
    private_constant :LOADING_CODE

    def call(command, config)
      with_loading_retry(config) { super }
    end

    def call_pipelined(commands, config)
      with_loading_retry(config) { super }
    end

    private

    def with_loading_retry(config)
      attempts = config.custom[:loading_retry_attempts] || []
      attempt = 0

      begin
        yield
      rescue RedisClient::CommandError => e
        raise unless e.code == LOADING_CODE
        raise if attempt >= attempts.size

        interval = attempts[attempt]
        Rails.logger.warn(
          "Redis replied LOADING, retrying in #{interval}s (attempt #{attempt + 1}/#{attempts.size})"
        )
        sleep(interval)
        attempt += 1
        retry
      end
    end
  end
end
