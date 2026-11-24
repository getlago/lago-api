# frozen_string_literal: true

module Types
  module RateCardUsages
    class RateSourceEnum < Types::BaseEnum
      graphql_name "RateCardUsageRateSourceEnum"

      value "rate"
      value "phase_override"
    end
  end
end
