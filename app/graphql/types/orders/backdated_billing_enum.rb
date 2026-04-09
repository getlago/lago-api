# frozen_string_literal: true

module Types
  module Orders
    class BackdatedBillingEnum < Types::BaseEnum
      Order::BACKDATED_BILLING_OPTIONS.keys.each do |option|
        value option
      end
    end
  end
end
