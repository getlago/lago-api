# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module PaymentProviders
    class ProviderTypeEnum < Types::BaseEnum
      Customer::PAYMENT_PROVIDERS.each do |type|
        value type
      end
    end
  end
end
