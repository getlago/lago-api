# frozen_string_literal: true

module Types
  module X402
    class Settlement < Types::BaseObject
      graphql_name "X402Settlement"

      dataload_association :wallet_transaction, :x402_connection

      field :id, ID, null: false

      field :asset, Types::X402::AssetEnum, null: false
      field :credit_amount, String, null: true
      field :kind, Types::X402::SettlementKindEnum, null: false
      field :network, String, null: false
      field :payee_address, String, null: false
      field :payer_address, String, null: false
      field :settled_amount_cents, GraphQL::Types::BigInt, null: false
      field :status, Types::X402::SettlementStatusEnum, null: false

      delegate :asset, to: :x402_connection

      def credit_amount
        wallet_transaction&.credit_amount
      end
    end
  end
end
