# frozen_string_literal: true

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

  Karafka.monitor.subscribe(
    WaterDrop::Instrumentation::LoggerListener.new(
      Karafka.logger,
      log_messages: true
    )
  )

  Karafka.monitor.subscribe "error.occurred" do |event|
    Sentry.capture_exception(event[:error])
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
end

Karafka::Process.tags.add(:application_name, "lago-api")

Karafka::Web.setup do |config|
  # Set this to false in all apps except one
  config.processing.active = ENV["LAGO_KARAFKA_PROCESSING"] if ENV["LAGO_KARAFKA_PROCESSING"].present?
  config.ui.sessions.secret = ENV["LAGO_KARAFKA_WEB_SECRET"] if ENV["LAGO_KARAFKA_WEB_SECRET"].present?
end

Karafka::Web.enable! if ENV["LAGO_KARAFKA_WEB"].present?
