# frozen_string_literal: true

require "active_support/core_ext/integer/time"
require "opentelemetry/sdk"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.
  config.middleware.use(ActionDispatch::Cookies)
  config.middleware.use(ActionDispatch::Session::CookieStore, key: "_lago_production")

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot. This eager loads most of Rails and
  # your application in memory, allowing both threaded web servers
  # and those relying on copy on write to perform better.
  # Rake tasks automatically ignore this option for performance.
  config.eager_load = true

  # Full error reports are disabled and caching is turned on.
  config.consider_all_requests_local = false

  # Ensures that a master key has been made available in ENV["RAILS_MASTER_KEY"], config/master.key, or an environment
  # key such as config/credentials/production.key. This key is used to decrypt credentials (and other encrypted files).
  # config.require_master_key = true

  # Disable serving static files from `public/`, relying on NGINX/Apache to do so instead.
  config.public_file_server.enabled = ENV["RAILS_SERVE_STATIC_FILES"].present?

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Specifies the header that your server uses for sending files.
  # config.action_dispatch.x_sendfile_header = "X-Sendfile" # for Apache
  # config.action_dispatch.x_sendfile_header = "X-Accel-Redirect" # for NGINX

  # Store uploaded files on the local file system (see config/storage.yml for options).
  config.active_storage.service = if ENV["LAGO_USE_AWS_S3"].present? && ENV["LAGO_USE_AWS_S3"] == "true"
    if ENV["LAGO_AWS_S3_ENDPOINT"].present? && !ENV["LAGO_AWS_S3_ENDPOINT"].empty?
      :amazon_compatible_endpoint
    else
      :amazon
    end
  elsif ENV["LAGO_USE_GCS"].present? && ENV["LAGO_USE_GCS"] == "true"
    :google
  else
    :local
  end

  # Mount Action Cable outside main process or domain.
  # config.action_cable.mount_path = nil
  # config.action_cable.url = "wss://example.com/cable"
  # config.action_cable.allowed_request_origins = [ "http://example.com", /http:\/\/example.*/ ]

  # Assume all access to the app is happening through a SSL-terminating reverse proxy.
  # Can be used together with config.force_ssl for Strict-Transport-Security and secure cookies.
  config.assume_ssl = true

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  config.force_ssl = false

  # Skip http-to-https redirect for the default health check endpoint.
  # config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }

  # Log to STDOUT by default
  if ENV["RAILS_LOG_TO_STDOUT"].present? && ENV["RAILS_LOG_TO_STDOUT"] == "true"
    config.logger = ActiveSupport::Logger.new(STDOUT)
      .tap { |logger| logger.formatter = ::Logger::Formatter.new }
      .then { |logger| ActiveSupport::TaggedLogging.new(logger) }
  end

  # Prepend all log lines with the following tags.
  config.log_tags = [:request_id]

  # "info" includes generic and useful information about system operation, but avoids logging too much
  # information to avoid inadvertent exposure of personally identifiable information (PII). If you
  # want to log everything, set the level to "debug".
  config.log_level = if ENV["LAGO_LOG_LEVEL"].present? && ENV["LAGO_LOG_LEVEL"] != ""
    ENV["LAGO_LOG_LEVEL"].downcase.to_sym
  else
    :info
  end

  # Use a different cache store in production.
  # config.cache_store = :mem_cache_store

  # Use a real queuing backend for Active Job (and separate queues per environment).
  # config.active_job.queue_adapter = :resque
  # config.active_job.queue_name_prefix = "lago_api_production"

  # Disable caching for Action Mailer templates even if Action Controller
  # caching is enabled.
  config.action_mailer.perform_caching = false

  # Ignore bad email addresses and do not raise email delivery errors.
  # Set this to true and configure the email server for immediate delivery to raise delivery errors.
  # config.action_mailer.raise_delivery_errors = false

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [:id]

  # Enable DNS rebinding protection and other `Host` header attacks.
  # config.hosts = [
  #   "example.com",     # Allow requests from example.com
  #   /.*\.example\.com/ # Allow requests from subdomains like `www.example.com`
  # ]
  # Skip DNS rebinding protection for the default health check endpoint.
  # config.host_authorization = { exclude: ->(request) { request.path == "/up" } }

  if ENV["LAGO_MEMCACHE_SERVERS"].present?
    config.cache_store = :mem_cache_store, ENV["LAGO_MEMCACHE_SERVERS"].split(",")

  elsif ENV["LAGO_REDIS_CACHE_URL"].present?
    cache_store_config = {
      url: ENV["LAGO_REDIS_CACHE_URL"],
      ssl_params: {
        verify_mode: OpenSSL::SSL::VERIFY_NONE
      },
      pool: {size: ENV.fetch("LAGO_REDIS_CACHE_POOL_SIZE", 5)},
      error_handler: lambda { |method:, returning:, exception:|
        Rails.logger.error(exception.message)
        Rails.logger.error(exception.backtrace.join("\n"))

        Sentry.capture_exception(exception)
      }
    }

    if ENV["LAGO_REDIS_CACHE_PASSWORD"].present? && !ENV["LAGO_REDIS_CACHE_PASSWORD"].empty?
      cache_store_config = cache_store_config.merge({password: ENV["LAGO_REDIS_CACHE_PASSWORD"]})
    end

    config.cache_store = :redis_cache_store, cache_store_config
  end

  config.license_url = if ENV["LAGO_CLOUD"] == "true" && ENV["RAILS_ENV"] == "staging"
    "http://license-web.default.svc.cluster.local"
  else
    "https://license.getlago.com"
  end

  if ENV["LAGO_SMTP_ADDRESS"].present? && !ENV["LAGO_SMTP_ADDRESS"].empty?
    config.action_mailer.delivery_method = :smtp
    config.action_mailer.smtp_settings = {
      address: ENV["LAGO_SMTP_ADDRESS"],
      port: ENV["LAGO_SMTP_PORT"],
      domain: ENV["LAGO_SMTP_DOMAIN"],
      user_name: ENV["LAGO_SMTP_USERNAME"],
      password: ENV["LAGO_SMTP_PASSWORD"],
      authentication: "login",
      enable_starttls_auto: true
    }
  end
end
