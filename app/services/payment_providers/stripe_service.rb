# frozen_string_literal: true

module PaymentProviders
  class StripeService < BaseService
    def create_or_update(**args)
      stripe_provider = PaymentProviders::StripeProvider.find_or_initialize_by(
        organization_id: args[:organization_id],
      )

      stripe_provider.secret_key = args[:secret_key] if args.key?(:secret_key)
      stripe_provider.create_customers = args[:create_customers]
      stripe_provider.send_zero_amount_invoice = args[:send_zero_amount_invoice]
      stripe_provider.save!

      result.stripe_provider = stripe_provider
      result
    rescue ActiveRecord::RecordInvalid => e
      result.fail_with_validations!(e.record)
    end
  end
end
