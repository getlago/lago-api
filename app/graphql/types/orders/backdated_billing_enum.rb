# frozen_string_literal: true

module Types
  module Orders
    class BackdatedBillingEnum < Types::BaseEnum
      graphql_name "OrderBackdatedBillingEnum"

      Order::BACKDATED_BILLING_OPTIONS.keys.each do |type|
        value type
      end
    end
  end
end
