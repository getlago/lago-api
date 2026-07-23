# frozen_string_literal: true

module Types
  module RateCards
    class RegroupPaidFeesEnum < Types::BaseEnum
      graphql_name "RateCardRegroupPaidFeesEnum"

      RateCard::REGROUP_PAID_FEES.keys.each do |type|
        value type
      end
    end
  end
end
