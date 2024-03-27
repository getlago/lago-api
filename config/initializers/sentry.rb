# frozen_string_literal: true

if ENV["SENTRY_DSN"]
  Sentry.init do |config|
    config.dsn = ENV["SENTRY_DSN"]
    config.breadcrumbs_logger = %i[active_support_logger http_logger]
    config.traces_sample_rate = 0
    config.environment = ENV["SENTRY_ENVIRONMENT"] || Rails.env
  end
end
