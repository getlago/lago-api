# frozen_string_literal: true

module Types
  module CreditNotes
    class Object < Types::BaseObject
      graphql_name 'CreditNote'

      field :id, ID, null: false
      field :sequential_id, ID, null: false
      field :number, String, null: false

      field :status, Types::CreditNotes::StatusTypeEnum, null: false
      field :reason, Types::CreditNotes::ReasonTypeEnum, null: false

      field :amount_cents, GraphQL::Types::BigInt, null: false
      field :amount_currency, Types::CurrencyEnum, null: false

      field :remaining_amount_cents, GraphQL::Types::BigInt, null: false
      field :remaining_amount_currency, Types::CurrencyEnum, null: false

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false

      # TODO: Expose credit note document
      # field :file_url, String, null: true

      field :invoice, Types::Invoices::Object
      field :items, [Types::CreditNoteItems::Object], null: false
    end
  end
end
