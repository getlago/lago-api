# frozen_string_literal: true

module Types
  module CreditNotes
    module AppliedTaxes
      class Object < Types::BaseObject
        graphql_name 'CreditNoteAppliedTax'

        field :id, ID, null: false

        field :credit_note, Types::CreditNotes::Object, null: false
        field :tax, Types::Taxes::Object, null: false

        field :tax_code, String, null: false
        field :tax_description, String, null: true
        field :tax_name, String, null: false
        field :tax_rate, Float, null: false

        field :amount_cents, GraphQL::Types::BigInt, null: false
        field :amount_currency, Types::CurrencyEnum, null: false

        field :created_at, GraphQL::Types::ISO8601DateTime, null: false
        field :updated_at, GraphQL::Types::ISO8601DateTime, null: false
      end
    end
  end
end
