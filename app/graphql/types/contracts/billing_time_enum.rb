# frozen_string_literal: true

module Types
  module Contracts
    class BillingTimeEnum < Types::BaseEnum
      graphql_name "ContractBillingTimeEnum"

      Contract::BILLING_TIMES.each_key do |type|
        value type
      end
    end
  end
end
