# frozen_string_literal: true

module Events
  class KafkaProducerService < BaseService
    Result = BaseResult

    EVENT_SOURCE = "http_ruby"

    def initialize(events:, organization:)
      @events = Array.wrap(events)
      @organization = organization
      super
    end

    def call
      return result if ENV["LAGO_KAFKA_BOOTSTRAP_SERVERS"].blank?
      return result if topic.blank?

      messages = events.map { |event| build_message(event) }
      Karafka.producer.produce_many_async(messages)

      result
    end

    private

    attr_reader :events, :organization

    # Product catalog organizations get their own pipeline, falling back to the
    # legacy topic until the catalog topic is configured.
    def catalog_pipeline?
      return @catalog_pipeline if defined?(@catalog_pipeline)

      @catalog_pipeline = organization.product_catalog_enabled? && ENV["LAGO_KAFKA_CATALOG_RAW_EVENTS_TOPIC"].present?
    end

    def topic
      catalog_pipeline? ? ENV["LAGO_KAFKA_CATALOG_RAW_EVENTS_TOPIC"] : ENV["LAGO_KAFKA_RAW_EVENTS_TOPIC"]
    end

    def build_message(event)
      {
        topic:,
        payload: build_payload(event).to_json
      }
    end

    def build_payload(event)
      {
        organization_id: organization.id,
        external_customer_id: event.external_customer_id,
        **scope_key(event),
        transaction_id: event.transaction_id,
        # NOTE: Removes trailing 'Z' to allow clickhouse parsing
        timestamp: event.timestamp.to_f.to_s,
        code: event.code,
        # NOTE: Default value to 0.0 is required for clickhouse parsing
        precise_total_amount_cents: event.precise_total_amount_cents.present? ? event.precise_total_amount_cents.to_s : "0.0",
        properties: event.properties,
        ingested_at: Time.zone.now.iso8601(3)[...-1],
        source: EVENT_SOURCE,
        source_metadata: {
          api_post_processed: !organization.clickhouse_events_store?
        }
      }
    end

    # The create services store external_contract_id in external_subscription_id;
    # the catalog tables key on the contract.
    def scope_key(event)
      if catalog_pipeline?
        {external_contract_id: event.external_subscription_id}
      else
        {external_subscription_id: event.external_subscription_id}
      end
    end
  end
end
