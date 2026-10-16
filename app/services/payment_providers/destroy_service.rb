# frozen_string_literal: true

module PaymentProviders
  class DestroyService < BaseService
    Result = BaseResult[:payment_provider]

    def initialize(payment_provider)
      @payment_provider = payment_provider

      super
    end

    def call
      return result.not_found_failure!(resource: "payment_provider") unless payment_provider
      return result.not_allowed_failure!(code: "payment_provider_used_by_agent_storefront") if used_by_agent_storefront?

      customer_ids = payment_provider.customer_ids

      ActiveRecord::Base.transaction do
        now = Time.current
        payment_provider.payment_provider_customers.update_all(updated_at: now, deleted_at: now) # rubocop:disable Rails/SkipsModelValidations
        payment_provider.discard!

        Customer.where(id: customer_ids).update_all(payment_provider: nil, payment_provider_code: nil) # rubocop:disable Rails/SkipsModelValidations
      end

      # TODO: Create job to unregister webhook

      result.payment_provider = payment_provider
      register_security_log
      result
    end

    private

    attr_reader :payment_provider

    def used_by_agent_storefront?
      payment_provider.is_a?(PaymentProviders::StripeProvider) &&
        payment_provider.organization.agent_storefront_integrations.with_payment_provider_code(payment_provider.code).exists?
    end

    def register_security_log
      Utils::SecurityLog.produce(
        organization: payment_provider.organization,
        log_type: "integration",
        log_event: "integration.deleted",
        resources: {
          integration_name: payment_provider.name,
          integration_type: payment_provider.class.name.demodulize.delete_suffix("Provider").underscore
        }
      )
    end
  end
end
