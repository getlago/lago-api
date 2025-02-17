# frozen_string_literal: true

require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module LagoApi
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 7.2

    # Disable YJIT as we are not ready yet
    config.yjit = false

    # TODO: Should be turned to false
    config.add_autoload_paths_to_load_path = true
    # config.autoload_lib(ignore: %w[task])
    config.eager_load_paths += %W[
      #{config.root}/lib
      #{config.root}/lib/lago_http_client
      #{config.root}/lib/lago_utils
      #{config.root}/lib/lago_eu_vat
      #{config.root}/app/views/helpers
      #{config.root}/app/support
    ]

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Only loads a smaller set of middleware suitable for API only apps.
    # Middleware like session, flash, cookies can be added back manually.
    # Skip views, helpers and assets when generating a new resource.
    config.api_only = true
    config.active_job.queue_adapter = :sidekiq

    # Configuration for active record encryption
    config.active_record.encryption.hash_digest_class = OpenSSL::Digest::SHA1
    config.active_record.encryption.primary_key = ENV["ENCRYPTION_PRIMARY_KEY"] || ENV["LAGO_ENCRYPTION_PRIMARY_KEY"]
    config.active_record.encryption.deterministic_key = ENV["ENCRYPTION_DETERMINISTIC_KEY"] || ENV["LAGO_ENCRYPTION_DETERMINISTIC_KEY"]
    config.active_record.encryption.key_derivation_salt = ENV["ENCRYPTION_KEY_DERIVATION_SALT"] || ENV["LAGO_ENCRYPTION_KEY_DERIVATION_SALT"]

    config.i18n.load_path += Dir[Rails.root.join("config/locales/**/*.{rb,yml}")]
    config.i18n.available_locales = %i[en fr nb de it es sv]
    config.i18n.default_locale = :en

    config.generators do |g|
      g.orm(:active_record, primary_key_type: :uuid)
    end

    config.active_support.cache_format_version = 7.1
  end
end

require_relative "../lib/active_job/uniqueness/strategies/until_executed_patch"
