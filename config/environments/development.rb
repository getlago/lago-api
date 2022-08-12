# frozen_string_literal: true

require 'active_support/core_ext/integer/time'
require 'sprockets/railtie'

Rails.application.configure do
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

  config.active_storage.service = if ENV['LAGO_USE_AWS_S3'].present?
    if ENV['LAGO_AWS_S3_ENDPOINT'].present?
      :amazon_compatible_endpoint
    else
      :amazon
    end
  else
    :local
  end

  config.action_mailer.raise_delivery_errors = false
  config.action_mailer.perform_caching = false
  config.active_support.deprecation = :log
  config.active_support.disallowed_deprecation = :raise
  config.active_support.disallowed_deprecation_warnings = []
  config.active_record.migration_error = :page_load
  config.active_record.verbose_query_logs = true

  config.hosts << 'api.lago.dev'
  config.hosts << 'api'

  Dotenv.load
end
