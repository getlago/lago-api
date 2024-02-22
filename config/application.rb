# frozen_string_literal: true

require_relative 'boot'

require 'rails/all'

Bundler.require(*Rails.groups)

module LagoApi
  class Application < Rails::Application
    config.load_defaults(7.0)
    config.eager_load_paths += %W[
      #{config.root}/lib
      #{config.root}/lib/lago_http_client
      #{config.root}/lib/lago_utils
      #{config.root}/lib/lago_eu_vat
      #{config.root}/app/views/helpers
    ]
    config.api_only = true
    config.active_job.queue_adapter = :sidekiq

    # Configuration for active record encryption
    config.active_record.encryption.primary_key = ENV['ENCRYPTION_PRIMARY_KEY']
    config.active_record.encryption.deterministic_key = ENV['ENCRYPTION_DETERMINISTIC_KEY']
    config.active_record.encryption.key_derivation_salt = ENV['ENCRYPTION_KEY_DERIVATION_SALT']

    config.i18n.load_path += Dir[Rails.root.join('config/locales/**/*.{rb,yml}')]
    config.i18n.available_locales = %i[en fr nb de it es sv]
    config.i18n.default_locale = :en

    config.session_store(:cookie_store, key: '_lago_session')
    config.middleware.use(ActionDispatch::Cookies)
    config.middleware.use(config.session_store, config.session_options)

    config.generators do |g|
      g.orm(:active_record, primary_key_type: :uuid)
    end
  end
end
