# frozen_string_literal: true

module PaymentProviders
  class StripeService < BaseService
    def create_or_update(**args)
      stripe_provider = PaymentProviders::StripeProvider.find_or_initialize_by(
        organization_id: args[:organization_id],
      )

      stripe_provider.update!(
        public_key: args[:public_key],
        secret_key: args[:secret_key],
      )

      result.stripe_provider = stripe_provider
      result
    rescue ActiveRecord::RecordInvalid => e
      result.fail_with_validations!(e.record)
    end
  end
end
