# frozen_string_literal: true

module Types
  module Wallets
    class AppliesTo < Types::BaseObject
      graphql_name "WalletAppliesTo"

      field :fee_types, [Types::Fees::TypesEnum], null: true

      def fee_types
        object.allowed_fee_types
      end
    end
  end
end
