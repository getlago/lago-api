# frozen_string_literal: true

# You can enable debug logging for Karafka by adding `debug: "topic"` to the `config.kafka` configuration. This will log
# debug information about topics (unknown topics, topic metadata, etc.) which can be helpful for troubleshooting Kafka
# connectivity issues locally.
#
class KarafkaApp < Karafka::App
  setup do |config|
    config.kafka = {
      "bootstrap.servers": ENV["LAGO_KAFKA_BOOTSTRAP_SERVERS"]
    }

    if ENV["LAGO_KAFKA_SECURITY_PROTOCOL"].present?
      config.kafka = config.kafka.merge({"security.protocol": ENV["LAGO_KAFKA_SECURITY_PROTOCOL"]})
    end

    if ENV["LAGO_KAFKA_SASL_MECHANISMS"].present?
      config.kafka = config.kafka.merge({"sasl.mechanisms": ENV["LAGO_KAFKA_SASL_MECHANISMS"]})
    end

    if ENV["LAGO_KAFKA_USERNAME"].present?
      config.kafka = config.kafka.merge({"sasl.username": ENV["LAGO_KAFKA_USERNAME"]})
    end

    if ENV["LAGO_KAFKA_PASSWORD"].present?
      config.kafka = config.kafka.merge({"sasl.password": ENV["LAGO_KAFKA_PASSWORD"]})
    end

    config.client_id = "Lago"
    # Recreate consumers with each batch. This will allow Rails code reload to work in the
    # development mode. Otherwise Karafka process would not be aware of code changes
    config.consumer_persistence = !Rails.env.development?

    config.monitor = Karafka::LagoMonitor.new
  end

  Karafka.monitor.subscribe(Karafka::Instrumentation::LoggerListener.new)

  Karafka.monitor.subscribe "error.occurred" do |event|
    Sentry.capture_exception(event[:error])
  end

  # Logs producer errors to Sentry.
  Karafka.producer.monitor.subscribe "error.occurred" do |event|
    Sentry.capture_exception(event[:error])
    Rails.logger.error("Karafka producer error: #{event[:error].message}")
  end

  if ENV["LAGO_KARAFKA_METRICS_PORT"].present?
    Karafka.monitor.subscribe("app.running") do
      exporter = Puma::Server.new(Yabeda::Prometheus::Exporter.rack_app)
      exporter.add_tcp_listener("0.0.0.0", Integer(ENV["LAGO_KARAFKA_METRICS_PORT"]))
      exporter.run
    rescue => e
      Rails.logger.error("Karafka metrics exporter failed to start: #{e.message}")
      Sentry.capture_exception(e)
    end
  end

  if ENV["LAGO_KAFKA_EVENTS_CHARGED_IN_ADVANCE_TOPIC"].present?
    routes.draw do
      consumer_group :lago_events_charged_in_advance_consumer do
        topic ENV["LAGO_KAFKA_EVENTS_CHARGED_IN_ADVANCE_TOPIC"] do
          consumer EventsChargedInAdvanceConsumer

          dead_letter_queue(topic: "unprocessed_events", max_retries: 1, independent: true, dispatch_method: :produce_sync)
        end
      end
    end
  end

  if ENV["LAGO_KAFKA_REALTIME_USAGE_TRIGGERS_TOPIC"].present?
    routes.draw do
      consumer_group :lago_wallet_refresh_triggers_consumer do
        topic ENV["LAGO_KAFKA_REALTIME_USAGE_TRIGGERS_TOPIC"] do
          consumer WalletRefreshTriggersConsumer

          # Wallet freshness: don't sit on a sparse batch (the default is 1000ms).
          max_wait_time 100
          # A batch collapses to one refresh per customer, so the collapse ratio has to be free to
          # grow with the backlog: under a small cap the consumer never catches up (measured: 98k
          # lag at a sustained 500 ev/s with 500). The distinct-customer count is what costs time,
          # and the consumer bounds it with its own deadline (WalletRefreshTriggersConsumer).
          max_messages 10_000
        end
      end
    end
  end
end

Karafka::Process.tags.add(:application_name, "lago-api")

Karafka::Web.setup do |config|
  # Set this to false in all apps except one
  config.processing.active = ENV["LAGO_KARAFKA_PROCESSING"] if ENV["LAGO_KARAFKA_PROCESSING"].present?
  config.ui.sessions.secret = ENV["LAGO_KARAFKA_WEB_SECRET"] if ENV["LAGO_KARAFKA_WEB_SECRET"].present?
end

Karafka::Web.enable! if ENV["LAGO_KARAFKA_WEB"].present?
