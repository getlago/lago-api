# frozen_string_literal: true

module Types
  module WalletTransactions
    class Object < Types::BaseObject
      graphql_name "WalletTransaction"

      field :id, ID, null: false
      field :wallet, Types::Wallets::Object

      field :amount, String, null: false
      field :credit_amount, String, null: false
      field :invoice_requires_successful_payment, Boolean, null: false
      field :status, Types::WalletTransactions::StatusEnum, null: false
      field :transaction_status, Types::WalletTransactions::TransactionStatusEnum, null: false
      field :transaction_type, Types::WalletTransactions::TransactionTypeEnum, null: false

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :failed_at, GraphQL::Types::ISO8601DateTime, null: true
      field :invoice, Types::Invoices::Object, null: true
      field :metadata, [Types::WalletTransactions::MetadataObject], null: true
      field :settled_at, GraphQL::Types::ISO8601DateTime, null: true
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false

      def invoice
        return object.invoice if object.invoice_id.present?

        fee = Fee.find_by(invoiceable_id: object.id, invoiceable_type: "WalletTransaction")
        fee&.invoice
      end
    end
  end
end
