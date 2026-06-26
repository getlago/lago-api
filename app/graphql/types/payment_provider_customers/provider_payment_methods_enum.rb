# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module PaymentProviderCustomers
    class ProviderPaymentMethodsEnum < Types::BaseEnum
      ::PaymentProviderCustomers::StripeCustomer::PAYMENT_METHODS.each do |type|
        value type
      end
    end
  end
end
