# frozen_string_literal: true

module Integrations
  class BaseKafkaProducerService < BaseService
    Result = BaseResult

    def initialize(integration:, event_type:, payload:)
      @integration = integration
      @event_type = event_type
      @payload = payload
      super
    end

    def call
      return result unless self.class.available?

      Karafka.producer.produce_async(
        topic: topic,
        key: kafka_key,
        payload: message_envelope.to_json
      )

      reuslt
    end

    def self.available?
      ENV["LAGO_KAFKA_BOOSTRAP_SERVERS"].present? && topic_configured?
    end

    def self.topic_configured?
      raise NotImplementedError, "Subclass must define topic_configured?"
    end

    private

    attr_reader :integration, :event_type, :payload

    def topic
      raise NotImplementedError, "Subclass must define topic"
    end

    def kafka_key
      "#{integration.organization_id}-#{integration_id}"
    end

    def message_envelope
      {
        event_type:,
        integration_id: integration.id,
        integration_type: integration.class.name,
        organization_id: integration.organization_id,
        account_id: integration.account_id,
        payload:,
        synced_at: Time.current.iso8601
      }
    end
  end
end
