# frozen_string_literal: true

module Types
  module RateCards
    class BillingTimingEnum < Types::BaseEnum
      graphql_name "RateCardBillingTimingEnum"

      RateCard::BILLING_TIMINGS.keys.each do |type|
        value type
      end
    end
  end
end
