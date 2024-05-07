# frozen_string_literal: true

ActiveJob::Uniqueness.configure do |config|
  config.lock_ttl = 1.hour

  if ENV['REDIS_PASSWORD'].present? && !ENV['REDIS_PASSWORD'].empty?
    uri = URI(ENV['REDIS_URL'])
    host = [uri.host, uri.path].join('')
    host = [host, uri.query].join('?')

    config.redlock_servers = ["redis://:#{ENV["REDIS_PASSWORD"]}@#{host}:#{uri.port}"]
  end
end
