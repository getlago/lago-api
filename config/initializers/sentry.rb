# frozen_string_literal: true

if ENV["SENTRY_DSN"].present?
  Sentry.init do |config|
    config.dsn = ENV["SENTRY_DSN"]
    config.release = LagoUtils::Version.call(default: Rails.env).sha_or_number
    config.breadcrumbs_logger = %i[active_support_logger http_logger]
    config.traces_sample_rate = 0
    config.traces_sample_rate = ENV["SENTRY_TRACES_SAMPLE_RATE"].to_f
    config.environment = ENV["SENTRY_ENVIRONMENT"] || Rails.env

    # Sentry keeps every header but Authorization and Cookie, and the cable token travels in this one.
    drop_websocket_protocol = lambda do |event, _hint|
      event.request&.headers&.delete("Sec-Websocket-Protocol")
      event
    end
    config.before_send = drop_websocket_protocol
    config.before_send_transaction = drop_websocket_protocol
  end
end
