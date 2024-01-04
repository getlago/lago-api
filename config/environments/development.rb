# frozen_string_literal: true

require 'active_support/core_ext/integer/time'
require 'sprockets/railtie'

Rails.application.configure do
  config.after_initialize do
    Bullet.enable        = true
    Bullet.rails_logger  = true
  end

  # Settings specified here will take precedence over those in config/application.rb.
  config.middleware.use(ActionDispatch::Cookies)
  config.middleware.use(ActionDispatch::Session::CookieStore, key: '_lago_dev')
  config.middleware.use(Rack::MethodOverride)

  config.cache_classes = false
  config.eager_load = false
  config.consider_all_requests_local = true
  config.server_timing = true

  if Rails.root.join('tmp/caching-dev.txt').exist?
    config.cache_store = :memory_store
    config.public_file_server.headers = {
      'Cache-Control' => "public, max-age=#{2.days.to_i}",
    }
  else
    config.action_controller.perform_caching = false

    config.cache_store = :null_store
  end

  config.active_storage.service = if ENV['LAGO_USE_AWS_S3'].present? && ENV['LAGO_USE_AWS_S3'] == 'true'
    if ENV['LAGO_AWS_S3_ENDPOINT'].present?
      :amazon_compatible_endpoint
    else
      :amazon
    end
  else
    :local
  end

  config.active_support.deprecation = :log
  config.active_support.disallowed_deprecation = :raise
  config.active_support.disallowed_deprecation_warnings = []
  config.active_record.migration_error = :page_load
  config.active_record.verbose_query_logs = true

  logger = ActiveSupport::Logger.new($stdout)
  logger.formatter = config.log_formatter
  config.logger = ActiveSupport::TaggedLogging.new(logger)

  config.hosts << 'api.lago.dev'
  config.hosts << 'api'
  config.hosts << 'lago.ngrok.dev'

  config.license_url = 'http://license:3000'

  config.action_mailer.perform_deliveries = true
  config.action_mailer.raise_delivery_errors = true
  config.action_mailer.delivery_method = :smtp
  config.action_mailer.smtp_settings = {
    address: 'mailhog',
    port: 1025,
  }

  Dotenv.load
end
