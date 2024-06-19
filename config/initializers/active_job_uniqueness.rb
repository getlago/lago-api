# frozen_string_literal: true

ActiveJob::Uniqueness.configure do |config|
  config.lock_ttl = 1.hour

  if ENV['REDIS_PASSWORD'].present? && !ENV['REDIS_PASSWORD'].empty?
    uri = URI(ENV['REDIS_URL'])
    host = [uri.host, uri.path].join('')
    
    if !uri.query.nil? && !uri.query.empty?
      host = [host, uri.query].join('?')
    end

    config.redlock_servers = ["#{uri.scheme}://:#{ENV["REDIS_PASSWORD"]}@#{host}:#{uri.port}"]
  end
end
