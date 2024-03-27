# frozen_string_literal: true

module WebhookEndpoints
  class CreateService < BaseService
    def initialize(organization:, params:)
      @organization = organization
      @params = params

      super
    end

    def call
      webhook_endpoint = organization.webhook_endpoints.new(
        webhook_url: params[:webhook_url],
        signature_algo: params[:signature_algo]&.to_sym || :jwt
      )

      webhook_endpoint.save!

      result.webhook_endpoint = webhook_endpoint
      track_webhook_webdpoint_created(result.webhook_endpoint)
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :organization, :params

    def track_webhook_webdpoint_created(webhook_endpoint)
      SegmentTrackJob.perform_later(
        membership_id: CurrentContext.membership,
        event: "webhook_endpoint_created",
        properties: {
          webhook_endpoint_id: webhook_endpoint.id,
          organization_id: webhook_endpoint.organization_id,
          webhook_url: webhook_endpoint.webhook_url
        }
      )
    end
  end
end
