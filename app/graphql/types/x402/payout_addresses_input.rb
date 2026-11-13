# frozen_string_literal: true

module Types
  module X402
    class PayoutAddressesInput < Types::BaseInputObject
      graphql_name "X402PayoutAddressesInput"

      argument :evm, String, required: false
      argument :svm, String, required: false
    end
  end
end
