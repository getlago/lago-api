# frozen_string_literal: true

module InboundWebhooks
  class CreateService < BaseService
    def initialize(organization_id:, webhook_source:, payload:, event_type:, code: nil, signature: nil)
      @organization_id = organization_id
      @webhook_source = webhook_source
      @code = code
      @payload = payload
      @signature = signature
      @event_type = event_type

      super
    end

    def call
      inbound_webhook = InboundWebhook.create!(
        organization_id:,
        source: webhook_source,
        code:,
        payload:,
        signature:,
        event_type:
      )

      after_commit do
        InboundWebhooks::ProcessJob.perform_later(inbound_webhook:)
      end

      result.inbound_webhook = inbound_webhook
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :organization_id, :webhook_source, :code, :payload, :signature, :event_type
  end
end
