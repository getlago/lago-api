# frozen_string_literal: true

module Types
  module X402
    class PayoutAddresses < Types::BaseObject
      graphql_name "X402PayoutAddresses"

      field :evm, String, null: true, hash_key: "evm"
      field :svm, String, null: true, hash_key: "svm"
    end
  end
end
