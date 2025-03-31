# frozen_string_literal: true

ActiveJob::Uniqueness.configure do |config|
  config.lock_ttl = 1.hour

  config.redlock_options = {
    retry_count: 3,
    redis_timeout: 5,
    retry_delay: 200,
    # random delay to avoid lock contention
    retry_jitter: 50
  }

  if ENV["REDIS_PASSWORD"].present? && !ENV["REDIS_PASSWORD"].empty?
    uri = URI(ENV["REDIS_URL"])
    host = [uri.host, uri.path].join("")

    if uri.query.present?
      host = [host, uri.query].join("?")
    end

    config.redlock_servers = [RedisClient.new(url: "#{uri.scheme}://:#{ENV["REDIS_PASSWORD"]}@#{host}:#{uri.port}", reconnect_attempts: 4)]
  end
end
