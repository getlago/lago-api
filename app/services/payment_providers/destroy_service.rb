# frozen_string_literal: true

module PaymentProviders
  class DestroyService < BaseService
    def destroy(id:)
      payment_provider = PaymentProviders::BaseProvider.find_by(
        id:,
        organization_id: result.user.organization_ids
      )
      return result.not_found_failure!(resource: 'payment_provider') unless payment_provider

      customer_ids = payment_provider.customer_ids

      payment_provider.payment_provider_customers.update_all(payment_provider_id: nil) # rubocop:disable Rails/SkipsModelValidations
      payment_provider.discard!

      Customer.where(id: customer_ids).update_all(payment_provider: nil, payment_provider_code: nil) # rubocop:disable Rails/SkipsModelValidations

      result.payment_provider = payment_provider
      result
    end
  end
end
