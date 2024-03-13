# frozen_string_literal: true

if ENV['SENTRY_DSN']
  Sentry.init do |config|
    config.dsn = ENV['SENTRY_DSN']
    config.release = Utils::VersionService.new.version.version.number
    config.breadcrumbs_logger = %i[active_support_logger http_logger]
    config.traces_sample_rate = ENV['SENTRY_TRACES_SAMPLE_RATE'].to_f || 0
  end
end
