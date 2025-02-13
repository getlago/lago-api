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
  end

  # Karafka.monitor.subscribe(Karafka::Instrumentation::ProctitleListener.new)

  # This logger prints the producer development info using the Karafka logger.
  # It is similar to the consumer logger listener but producer oriented.
  Karafka.producer.monitor.subscribe(
    WaterDrop::Instrumentation::LoggerListener.new(
      # Log producer operations using the Karafka logger
      Karafka.logger,
      # If you set this to true, logs will contain each message details
      # Please note, that this can be extensive
      log_messages: false
    )
  )

  routes.draw do
    consumer_group :lago do
      topic ENV['LAGO_KAFKA_RAW_EVENTS_TOPIC'] do
        consumer EventsConsumer

        dead_letter_queue(topic: 'unprocessed_events', max_retries: 1, independent: true, dispatch_method: :produce_sync)
      end
    end
  end
end

Karafka::Web.setup do |config|
  # Set this to false in all apps except one
  config.processing.active = false

  if ENV["LAGO_KARAFKA_WEB_SECRET"].present?
    config.ui.sessions.secret = ENV["LAGO_KARAFKA_WEB_SECRET"]
  end
end

Karafka::Web.enable! if ENV["LAGO_KARAFKA_WEB"]

Karafka::Process.tags.add(:application_name, "lago-api")
