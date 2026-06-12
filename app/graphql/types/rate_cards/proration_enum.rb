# frozen_string_literal: true

module Types
  module RateCards
    class ProrationEnum < Types::BaseEnum
      graphql_name "RateCardProrationEnum"

      RateCard::PRORATIONS.keys.each do |type|
        value type
      end
    end
  end
end
