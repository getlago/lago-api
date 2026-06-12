# frozen_string_literal: true

module Types
  module RateCardRates
    class BillingIntervalUnitEnum < Types::BaseEnum
      graphql_name "RateCardRateBillingIntervalUnitEnum"

      RateCardRate::BILLING_INTERVAL_UNITS.keys.each do |type|
        value type
      end
    end
  end
end
