# frozen_string_literal: true

module WebhookEndpoints
  class UpdateService < BaseService
    Result = BaseResult[:webhook_endpoint]

    def initialize(id:, organization:, params:, signature_algo_rule: nil)
      @id = id
      @organization = organization
      @params = params
      @signature_algo_rule = signature_algo_rule || WebhookEndpoint.v1_signature_algo_rule(organization)

      super
    end

    def call
      webhook_endpoint = organization.webhook_endpoints.find_by(id:)

      return result.not_found_failure!(resource: "webhook_endpoint") if webhook_endpoint.blank?

      # Only a change is checked, so an endpoint keeps an algorithm the API no longer offers.
      # The column is NOT NULL, so null is refused like an unknown value.
      if signature_algo_changed?(webhook_endpoint) && !signature_algo_rule.allow?(params[:signature_algo])
        return invalid_signature_algo_failure
      end

      ActiveRecord::Base.transaction do
        webhook_endpoint.webhook_url = params[:webhook_url] if params.key?(:webhook_url)
        webhook_endpoint.signature_algo = params[:signature_algo] if params.key?(:signature_algo)
        webhook_endpoint.name = params[:name] if params.key?(:name)
        webhook_endpoint.event_types = params[:event_types] if params.key?(:event_types)
        webhook_endpoint.save!

        # Only a switch to standard_webhooks needs a key: the key service reuses the one kept from an earlier switch.
        switched_to_standard_webhooks = webhook_endpoint.standard_webhooks? && webhook_endpoint.saved_change_to_signature_algo?
        register_security_log(webhook_endpoint)
        SigningKeys::CreateService.call!(webhook_endpoint:) if switched_to_standard_webhooks
      end

      result.webhook_endpoint = webhook_endpoint
      result
    rescue ActiveRecord::RecordInvalid => e
      failure = BaseService::ValidationFailure.from_errors(result, e.record.errors)
      result.validation_failure!(errors: failure.messages, meta: failure.meta, codes: WebhookEndpoint.validation_codes(e.record.errors))
    end

    private

    attr_reader :id, :organization, :params, :signature_algo_rule

    def signature_algo_changed?(webhook_endpoint)
      params.key?(:signature_algo) && params[:signature_algo].to_s != webhook_endpoint.signature_algo
    end

    def invalid_signature_algo_failure
      result.single_validation_failure!(
        field: :signature_algo,
        error_code: "value_is_invalid",
        meta: {allowed_values: signature_algo_rule.allowed_values}
      )
    end

    def register_security_log(webhook_endpoint)
      diff = webhook_endpoint.previous_changes.slice("webhook_url", "signature_algo").to_h
        .transform_keys(&:to_sym)
        .transform_values { |v| {deleted: v[0], added: v[1]}.compact }

      resources = {webhook_url: webhook_endpoint.webhook_url, **diff}

      # Deferred so nothing is sent when an outer transaction rolls back. The diff is read
      # now: a later save of the same record in that transaction replaces previous_changes.
      after_commit do
        Utils::SecurityLog.produce(
          organization: webhook_endpoint.organization,
          log_type: "webhook_endpoint",
          log_event: "webhook_endpoint.updated",
          resources:
        )
      end
    end
  end
end
