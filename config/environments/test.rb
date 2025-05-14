# frozen_string_literal: true

require "active_support/core_ext/integer/time"

Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = ENV["CI"].present?

  config.public_file_server.enabled = true
  config.public_file_server.headers = {
    "Cache-Control" => "public, max-age=#{1.hour.to_i}"
  }

  config.logger = Logger.new(nil)
  config.log_level = :fatal

  config.consider_all_requests_local = true
  config.action_controller.perform_caching = false
  config.cache_store = :null_store
  config.action_dispatch.show_exceptions = :rescuable
  config.action_controller.allow_forgery_protection = false
  config.active_storage.service = :test

  config.action_mailer.perform_caching = false
  config.action_mailer.delivery_method = :test
  config.action_mailer.default_url_options = {host: "www.example.com"}

  config.active_support.deprecation = :stderr
  config.active_support.disallowed_deprecation = :raise
  config.active_support.disallowed_deprecation_warnings = []

  config.action_controller.raise_on_missing_callback_actions = true

  config.active_record.encryption.primary_key = "test"
  config.active_record.encryption.deterministic_key = "test"
  config.active_record.encryption.key_derivation_salt = "test"

  config.active_job.queue_adapter = :test
  config.license_url = "http://license.lago"

  Dotenv.load

  if ENV["LAGO_REDIS_CACHE_URL"].present?
    redis_store_config = {
      url: ENV["LAGO_REDIS_CACHE_URL"],
      ssl_params: {verify_mode: OpenSSL::SSL::VERIFY_NONE}
    }
    config.cache_store = :redis_cache_store, redis_store_config
  end
  config.cache_store = :null_store

  # Set default API URL for test environment
  ENV["LAGO_API_URL"] ||= "http://localhost:3000"
end
