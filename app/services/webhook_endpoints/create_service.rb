# frozen_string_literal: true

module WebhookEndpoints
  class CreateService < BaseService
    Result = BaseResult[:webhook_endpoint]

    def initialize(organization:, params:)
      @organization = organization
      @params = params

      super
    end

    def call
      webhook_endpoint = organization.webhook_endpoints.new(
        webhook_url: params[:webhook_url],
        signature_algo:,
        name: params[:name],
        event_types: params[:event_types]
      )

      # A new endpoint has no concurrent writer, so it needs no row lock.
      ActiveRecord::Base.transaction do
        webhook_endpoint.save!
        WebhookEndpoints::SigningKeys::EnsureService.call!(webhook_endpoint:) if webhook_endpoint.standard_webhooks?
      end

      result.webhook_endpoint = webhook_endpoint
      # A caller's transaction can still roll the endpoint back.
      after_commit do
        track_webhook_webdpoint_created(webhook_endpoint)
        register_security_log(webhook_endpoint)
      end
      result
    rescue ActiveRecord::RecordInvalid => e
      failure = BaseService::ValidationFailure.from_errors(result, e.record.errors)
      result.validation_failure!(
        errors: failure.messages,
        meta: WebhookEndpoint.validation_meta(e.record, failure.meta),
        codes: WebhookEndpoint.validation_codes(e.record.errors)
      )
    end

    private

    attr_reader :organization, :params

    def signature_algo
      params[:signature_algo].nil? ? WebhookEndpoint.default_signature_algo(organization) : params[:signature_algo]
    end

    def register_security_log(webhook_endpoint)
      Utils::SecurityLog.produce(
        organization: organization,
        log_type: "webhook_endpoint",
        log_event: "webhook_endpoint.created",
        resources: {webhook_url: webhook_endpoint.webhook_url, signature_algo: webhook_endpoint.signature_algo}
      )
    end

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
