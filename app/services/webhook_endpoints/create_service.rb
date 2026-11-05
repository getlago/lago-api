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
      signature_algo = params[:signature_algo].nil? ? "jwt" : params[:signature_algo]
      return invalid_signature_algo_failure unless WebhookEndpoint.signature_algos.key?(signature_algo.to_s)

      webhook_endpoint = organization.webhook_endpoints.new(
        webhook_url: params[:webhook_url],
        signature_algo:,
        name: params[:name],
        event_types: params[:event_types]
      )

      webhook_endpoint.save!

      result.webhook_endpoint = webhook_endpoint
      # A caller's transaction can still roll the endpoint back.
      after_commit do
        track_webhook_webdpoint_created(webhook_endpoint)
        register_security_log(webhook_endpoint)
      end
      result
    rescue ActiveRecord::RecordInvalid => e
      failure = BaseService::ValidationFailure.from_errors(result, e.record.errors)
      result.validation_failure!(errors: failure.messages, meta: failure.meta, codes: WebhookEndpoint.validation_codes(e.record.errors))
    end

    private

    attr_reader :organization, :params

    def invalid_signature_algo_failure
      result.single_validation_failure!(
        field: :signature_algo,
        error_code: "value_is_invalid",
        meta: {allowed_values: WebhookEndpoint.signature_algos.keys}
      )
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
