# frozen_string_literal: true

module PaymentProviders
  class PaystackService < BaseService
    def create_or_update(**args)
      payment_provider_result = PaymentProviders::FindService.call(
        organization_id: args[:organization].id,
        code: args[:code],
        id: args[:id],
        payment_provider_type: "paystack"
      )

      paystack_provider = if payment_provider_result.success?
        payment_provider_result.payment_provider
      else
        PaymentProviders::PaystackProvider.new(
          organization_id: args[:organization].id,
          code: args[:code]
        )
      end

      old_code = paystack_provider.code

      paystack_provider.secret_key = args[:secret_key] if args.key?(:secret_key)
      paystack_provider.success_redirect_url = args[:success_redirect_url] if args.key?(:success_redirect_url)
      paystack_provider.code = args[:code] if args.key?(:code)
      paystack_provider.name = args[:name] if args.key?(:name)
      paystack_provider.save!

      if payment_provider_code_changed?(paystack_provider, old_code, args)
        paystack_provider.customers.update_all(payment_provider_code: args[:code]) # rubocop:disable Rails/SkipsModelValidations
      end

      result.paystack_provider = paystack_provider
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end
  end
end
