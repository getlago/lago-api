# frozen_string_literal: true

require 'socket'

LIVENESS_PORT = 8080

redis_config = {
  url: ENV['REDIS_URL'],
  pool_timeout: 5,
  ssl_params: {
    verify_mode: OpenSSL::SSL::VERIFY_NONE
  }
}

if ENV['REDIS_PASSWORD'].present? && !ENV['REDIS_PASSWORD'].empty?
  redis_config = redis_config.merge({password: ENV['REDIS_PASSWORD']})
end

if ENV['LAGO_SIDEKIQ_WEB'] == 'true'
  require 'sidekiq/web'
  Sidekiq::Web.use(ActionDispatch::Cookies)
  Sidekiq::Web.use(ActionDispatch::Session::CookieStore, key: '_interslice_session')
end

Sidekiq.configure_server do |config|
  config.redis = redis_config
  config.logger = Sidekiq::Logger.new($stdout)
  config.logger.formatter = Sidekiq::Logger::Formatters::JSON.new
  config[:max_retries] = 0
  config[:dead_max_jobs] = ENV.fetch("LAGO_SIDEKIQ_MAX_DEAD_JOBS", 100_000).to_i
  config.on(:startup) do
    Sidekiq.logger.info "Starting liveness server on #{LIVENESS_PORT}"
    Thread.start do
      server = TCPServer.new("localhost", LIVENESS_PORT)
      loop do
        Thread.start(server.accept) do |socket|
          request = socket.gets
          sidekiq_response = ::Sidekiq.redis { |r| r.ping }

          if sidekiq_response.eql?("PONG")
            response = "Live!\n"
            socket.print "HTTP/1.1 200 OK\r\n" \
                       "Content-Type: text/plain\r\n" \
                       "Content-Length: #{response.bytesize}\r\n" \
                       "Connection: close\r\n"
          else
            response = "Sidekiq is not ready: Sidekiq.redis.ping returned #{request.inspect} instead of PONG\n"
            Sidekiq.logger.error(response)
            socket.print "HTTP/1.1 404 OK\r\n" \
                       "Content-Type: text/plain\r\n" \
                       "Content-Length: #{response.bytesize}\r\n" \
                       "Connection: close\r\n"
          end
          socket.print "\r\n"
          socket.print response
          socket.close
        rescue
          response = "Sidekiq is not ready\n"
          Sidekiq.logger.error(response)
          socket.print "HTTP/1.1 404 OK\r\n" \
                       "Content-Type: text/plain\r\n" \
                       "Content-Length: #{response.bytesize}\r\n" \
                       "Connection: close\r\n"
          socket.print "\r\n"
          socket.print response
          socket.close
        end
      end
    end
  end
end

Sidekiq.configure_client do |config|
  config.redis = redis_config
  config.logger = Sidekiq::Logger.new($stdout)
  config.logger.formatter = Sidekiq::Logger::Formatters::JSON.new
end
