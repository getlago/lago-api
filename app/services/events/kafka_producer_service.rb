# frozen_string_literal: true

module Events
  class KafkaProducerService < BaseService
    Result = BaseResult

    EVENT_SOURCE = "http_ruby"

    def initialize(event:, organization:)
      @event = event
      @organization = organization
      super
    end

    def call
      return result if ENV["LAGO_KAFKA_BOOTSTRAP_SERVERS"].blank?
      return result if ENV["LAGO_KAFKA_RAW_EVENTS_TOPIC"].blank?

      Karafka.producer.produce_async(
        topic: ENV["LAGO_KAFKA_RAW_EVENTS_TOPIC"],
        key: "#{organization.id}-#{event.external_subscription_id}",
        payload: {
          organization_id: organization.id,
          external_customer_id: event.external_customer_id,
          external_subscription_id: event.external_subscription_id,
          transaction_id: event.transaction_id,
          # NOTE: Removes trailing 'Z' to allow clickhouse parsing
          timestamp: event.timestamp.to_f.to_s,
          code: event.code,
          # NOTE: Default value to 0.0 is required for clickhouse parsing
          precise_total_amount_cents: event.precise_total_amount_cents.present? ? event.precise_total_amount_cents.to_s : "0.0",
          properties: event.properties,
          ingested_at: Time.zone.now.iso8601[...-1],
          source: EVENT_SOURCE,
          source_metadata: {
            api_post_processed: !organization.clickhouse_events_store?
          }
        }.to_json
      )

      result
    end

    private

    attr_reader :event, :organization
  end
end
