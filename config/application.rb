# frozen_string_literal: true

require_relative 'boot'

require 'rails/all'

Bundler.require(*Rails.groups)

module LagoApi
  class Application < Rails::Application
    config.load_defaults(7.0)
    config.eager_load_paths << Rails.root.join('lib/lago_http_client')
    config.api_only = true
    config.active_job.queue_adapter = :sidekiq

    # Configuration for active record encryption
    config.active_record.encryption.primary_key = ENV['ENCRYPTION_PRIMARY_KEY']
    config.active_record.encryption.deterministic_key = ENV['ENCRYPTION_DETERMINISTIC_KEY']
    config.active_record.encryption.key_derivation_salt = ENV['ENCRYPTION_KEY_DERIVATION_SALT']

    config.generators do |g|
      g.orm :active_record, primary_key_type: :uuid
    end
  end
end
