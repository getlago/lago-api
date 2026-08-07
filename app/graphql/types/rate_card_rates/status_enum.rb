# frozen_string_literal: true

module Types
  module RateCardRates
    class StatusEnum < Types::BaseEnum
      graphql_name "RateCardRateStatusEnum"

      RateCardRate::STATUSES.keys.each do |type|
        value type
      end
    end
  end
end
