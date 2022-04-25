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
  end
end
