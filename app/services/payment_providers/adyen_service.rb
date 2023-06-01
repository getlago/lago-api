# frozen_string_literal: true

module PaymentProviders
  class AdyenService < BaseService
    def create_or_update(**args)
      adyen_provider = PaymentProviders::AdyenProvider.find_or_initialize_by(
        organization_id: args[:organization].id,
      )

      adyen_provider.api_key = args[:api_key] if args.key?(:api_key)
      adyen_provider.merchant_account = args[:merchant_account] if args.key?(:merchant_account)
      adyen_provider.live_prefix = args[:live_prefix] if args.key?(:live_prefix)
      adyen_provider.hmac_key = args[:hmac_key] if args.key?(:hmac_key)
      adyen_provider.save!

      result.adyen_provider = adyen_provider
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end
  end
end
