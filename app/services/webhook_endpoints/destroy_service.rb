# frozen_string_literal: true

module WebhookEndpoints
  class DestroyService < BaseService
    def initialize(webhook_endpoint:)
      @webhook_endpoint = webhook_endpoint

      super
    end

    def call
      return result.not_found_failure!(resource: "webhook_endpoint") unless webhook_endpoint

      webhook_endpoint.destroy!
      track_webhook_endpoint_deleted

      result.webhook_endpoint = webhook_endpoint
      result
    end

    private

    attr_reader :webhook_endpoint

    def track_webhook_endpoint_deleted
      SegmentTrackJob.perform_later(
        membership_id: CurrentContext.membership,
        event: "webhook_endpoint_deleted",
        properties: {
          webhook_endpoint_id: webhook_endpoint.id,
          organization_id: webhook_endpoint.organization_id,
          webhook_url: webhook_endpoint.webhook_url
        }
      )
    end
  end
end
