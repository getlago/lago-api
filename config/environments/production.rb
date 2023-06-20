# frozen_string_literal: true

require 'active_support/core_ext/integer/time'

Rails.application.configure do
  config.cache_classes = true
  config.eager_load = true
  config.consider_all_requests_local = false
  config.public_file_server.enabled = ENV['RAILS_SERVE_STATIC_FILES'].present?

  config.active_storage.service = if ENV['LAGO_USE_AWS_S3'].present? && ENV['LAGO_USE_AWS_S3'] == 'true'
    if ENV['LAGO_AWS_S3_ENDPOINT'].present? && !ENV['LAGO_AWS_S3_ENDPOINT'].empty?
      :amazon_compatible_endpoint
    else
      :amazon
    end
  elsif ENV['LAGO_USE_GCS'].present? && ENV['LAGO_USE_GCS'] == 'true'
    :google
  else
    :local
  end

  config.log_level = :info
  config.log_tags = [:request_id]
  config.action_mailer.perform_caching = false
  config.i18n.fallbacks = true
  config.active_support.report_deprecations = false
  config.log_formatter = ::Logger::Formatter.new

  if ENV['RAILS_LOG_TO_STDOUT'].present? && ENV['RAILS_LOG_TO_STDOUT'] == 'true'
    logger           = ActiveSupport::Logger.new($stdout)
    logger.formatter = config.log_formatter
    config.logger    = ActiveSupport::TaggedLogging.new(logger)
  end

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  if ENV['LAGO_MEMCACHE_SERVERS'].present?
    config.cache_store = :mem_cache_store, ENV['LAGO_MEMCACHE_SERVERS'].split(',')

  elsif ENV['LAGO_REDIS_CACHE_URL'].present?
    cache_store_config = {
      url: ENV['LAGO_REDIS_CACHE_URL'],
      ssl_params: {
        verify_mode: OpenSSL::SSL::VERIFY_NONE,
      },
      error_handler: lambda { |method:, returning:, exception:|
        Rails.logger.error(exception.message)
        Rails.logger.error(exception.backtrace.join("\n"))

        Sentry.capture_exception(exception)
      },
    }

    if ENV['LAGO_REDIS_CACHE_PASSWORD'].present? && !ENV['LAGO_REDIS_CACHE_PASSWORD'].empty?
      cache_store_config = cache_store_config.merge({ password: ENV['LAGO_REDIS_CACHE_PASSWORD'] })
    end

    config.cache_store = :redis_cache_store, cache_store_config
  end

  config.license_url = if ENV['LAGO_CLOUD'] == 'true' && ENV['RAILS_ENV'] == 'staging'
    'http://license-web.default.svc.cluster.local'
  else
    'https://license.getlago.com'
  end

  if ENV['LAGO_SMTP_ADDRESS'].present? && !ENV['LAGO_SMTP_ADDRESS'].empty?
    config.action_mailer.delivery_method = :smtp
    config.action_mailer.smtp_settings = {
      address: ENV['LAGO_SMTP_ADDRESS'],
      port: ENV['LAGO_SMTP_PORT'],
      domain: ENV['LAGO_SMTP_DOMAIN'],
      user_name: ENV['LAGO_SMTP_USERNAME'],
      password: ENV['LAGO_SMTP_PASSWORD'],
      authentication: 'login',
      enable_starttls_auto: true,
    }
  end
end
