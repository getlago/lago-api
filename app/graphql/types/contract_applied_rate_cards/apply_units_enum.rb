# frozen_string_literal: true

module Types
  module ContractAppliedRateCards
    class ApplyUnitsEnum < Types::BaseEnum
      graphql_name "ContractAppliedRateCardApplyUnitsEnum"

      value "now"
      value "next_billing_period"
    end
  end
end
