# frozen_string_literal: true

module Types
  module RateCardRates
    class RateModelEnum < Types::BaseEnum
      graphql_name "RateCardRateModelEnum"

      RateCardRate::RATE_MODELS.keys.each do |type|
        value type
      end
    end
  end
end
