# frozen_string_literal: true

module Types
  module PaymentProviderCustomers
    class StripeInput < BaseInputObject
      graphql_name 'StripeCustomerInput'

      argument :provider_customer_id, ID, required: false
    end
  end
end
