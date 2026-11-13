# frozen_string_literal: true

module WebhookEndpoints
  class CreateService < BaseService
    Result = BaseResult[:webhook_endpoint]

    def initialize(organization:, params:, signature_algo_rule: nil)
      @organization = organization
      @params = params
      @signature_algo_rule = signature_algo_rule || WebhookEndpoint.v1_signature_algo_rule(organization)

      super
    end

    def call
      signature_algo = params[:signature_algo].nil? ? signature_algo_rule.default : params[:signature_algo]
      return invalid_signature_algo_failure unless signature_algo_rule.allow?(signature_algo)

      webhook_endpoint = organization.webhook_endpoints.new(
        webhook_url: params[:webhook_url],
        signature_algo:,
        name: params[:name],
        event_types: params[:event_types]
      )

      ActiveRecord::Base.transaction do
        webhook_endpoint.save!
        SigningKeys::CreateService.call!(webhook_endpoint:) if webhook_endpoint.standard_webhooks?
      end

      result.webhook_endpoint = webhook_endpoint
      track_webhook_webdpoint_created(result.webhook_endpoint)
      # Deferred so nothing is sent when an outer transaction rolls back.
      after_commit { register_security_log(webhook_endpoint) }
      result
    rescue ActiveRecord::RecordInvalid => e
      failure = BaseService::ValidationFailure.from_errors(result, e.record.errors)
      result.validation_failure!(errors: failure.messages, meta: failure.meta, codes: WebhookEndpoint.validation_codes(e.record.errors))
    end

    private

    attr_reader :organization, :params, :signature_algo_rule

    def invalid_signature_algo_failure
      result.single_validation_failure!(
        field: :signature_algo,
        error_code: "value_is_invalid",
        meta: {allowed_values: signature_algo_rule.allowed_values}
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
      SegmentTrackJob.perform_after_commit(
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
