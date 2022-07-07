# frozen_string_literal: true

require 'active_support/core_ext/integer/time'

Rails.application.configure do
  config.cache_classes = true
  config.eager_load = true
  config.consider_all_requests_local = false
  config.public_file_server.enabled = ENV['RAILS_SERVE_STATIC_FILES'].present?

  config.active_storage.service = if ENV['LAGO_USE_AWS_S3']
    :amazon
  else
    :local
  end

  config.log_level = :info
  config.log_tags = [:request_id]
  config.action_mailer.perform_caching = false
  config.i18n.fallbacks = true
  config.active_support.report_deprecations = false
  config.log_formatter = ::Logger::Formatter.new

  if ENV['RAILS_LOG_TO_STDOUT'].present?
    logger           = ActiveSupport::Logger.new($stdout)
    logger.formatter = config.log_formatter
    config.logger    = ActiveSupport::TaggedLogging.new(logger)
  end

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  if ENV['LAGO_MEMCACHE_SERVERS'].present?
    config.cache_store = :mem_cache_store, ENV['LAGO_MEMCACHE_SERVERS'].split(',')

  elsif ENV['LAGO_REDIS_CACHE_URL'].present?
    config.cache_store = :redis_cache_store, {
      url: ENV['LAGO_REDIS_CACHE_URL'],
      error_handler: ->(method:, returning:, exception:) {
        Rails.logger.error(exception.message)
        Rails.logger.error(exception.backtrace.join("\n"))

        Sentry.capture_exception(exception)
      },
    }
  end
end
