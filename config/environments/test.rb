# frozen_string_literal: true

require 'active_support/core_ext/integer/time'

Rails.application.configure do
  config.cache_classes = true
  config.eager_load = ENV['CI'].present?
  config.public_file_server.enabled = true
  config.public_file_server.headers = {
    'Cache-Control' => "public, max-age=#{1.hour.to_i}",
  }

  config.logger = Logger.new(nil)
  config.log_level = :fatal

  config.consider_all_requests_local = true
  config.action_controller.perform_caching = false
  config.cache_store = :null_store
  config.action_dispatch.show_exceptions = false
  config.action_controller.allow_forgery_protection = false
  config.active_storage.service = :test

  config.action_mailer.perform_caching = false
  config.action_mailer.delivery_method = :test

  config.active_record.encryption.primary_key = 'test'
  config.active_record.encryption.deterministic_key = 'test'
  config.active_record.encryption.key_derivation_salt = 'test'

  config.active_support.deprecation = :stderr
  config.active_support.disallowed_deprecation = :raise
  config.active_support.disallowed_deprecation_warnings = []

  Dotenv.load

  config.active_job.queue_adapter = :test
  config.license_url = 'http://license.lago'
end
