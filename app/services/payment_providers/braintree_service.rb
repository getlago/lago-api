# frozen_string_literal: true

module PaymentProviders
  class BraintreeService < BaseService
    def create_or_update(**args)
      payment_provider_result = PaymentProviders::FindService.call(
        organization_id: args[:organization].id,
        code: args[:code],
        id: args[:id],
        payment_provider_type: "braintree"
      )

      braintree_provider = if payment_provider_result.success?
        payment_provider_result.payment_provider
      else
        PaymentProviders::BraintreeProvider.new(
          organization_id: args[:organization].id,
          code: args[:code]
        )
      end

      old_code = braintree_provider.code

      braintree_provider.public_key = args[:public_key] if args.key?(:public_key)
      braintree_provider.private_key = args[:private_key] if args.key?(:private_key)
      braintree_provider.code = args[:code] if args.key?(:code)
      braintree_provider.name = args[:name] if args.key?(:name)
      braintree_provider.merchant_id = args[:merchant_id] if args.key?(:merchant_id)
      braintree_provider.success_redirect_url = args[:success_redirect_url] if args.key?(:success_redirect_url)
      braintree_provider.save!

      if payment_provider_code_changed?(braintree_provider, old_code, args)
        braintree_provider.customers.update_all(payment_provider_code: args[:code]) # rubocop:disable Rails/SkipsModelValidations
      end

      result.braintree_provider = braintree_provider
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end
  end
end
