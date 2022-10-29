# frozen_string_literal: true

module Types
  module CreditNotes
    class Object < Types::BaseObject
      graphql_name 'CreditNote'

      field :id, ID, null: false
      field :sequential_id, ID, null: false
      field :number, String, null: false

      field :credit_status, Types::CreditNotes::CreditStatusTypeEnum, null: true
      field :refund_status, Types::CreditNotes::RefundStatusTypeEnum, null: true
      field :reason, Types::CreditNotes::ReasonTypeEnum, null: false

      field :total_amount_cents, GraphQL::Types::BigInt, null: false
      field :total_amount_currency, Types::CurrencyEnum, null: false

      field :credit_amount_cents, GraphQL::Types::BigInt, null: false
      field :credit_amount_currency, Types::CurrencyEnum, null: false

      field :balance_amount_cents, GraphQL::Types::BigInt, null: false
      field :balance_amount_currency, Types::CurrencyEnum, null: false

      field :refund_amount_cents, GraphQL::Types::BigInt, null: false
      field :refund_amount_currency, Types::CurrencyEnum, null: false

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false

      field :file_url, String, null: true

      field :invoice, Types::Invoices::Object
      field :items, [Types::CreditNoteItems::Object], null: false
    end
  end
end
