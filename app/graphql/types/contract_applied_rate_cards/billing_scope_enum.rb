# frozen_string_literal: true

module Types
  module ContractAppliedRateCards
    class BillingScopeEnum < Types::BaseEnum
      graphql_name "ContractAppliedRateCardBillingScopeEnum"

      ContractRateCard::BILLING_SCOPES.each_value { |scope| value scope }
    end
  end
end
