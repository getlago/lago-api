# frozen_string_literal: true

module Types
  module Fees
    class Object < Types::BaseObject
      graphql_name 'Fee'
      implements Types::Invoices::InvoiceItem

      field :charge, Types::Charges::Object, null: true
      field :subscription, Types::Subscriptions::Object, null: true

      field :vat_amount_cents, GraphQL::Types::BigInt, null: false
      field :vat_amount_currency, Types::CurrencyEnum, null: false

      field :vat_rate, GraphQL::Types::Float, null: true
      field :units, GraphQL::Types::Float, null: false
      field :events_count, GraphQL::Types::BigInt, null: true

      field :fee_type, Types::Fees::TypesEnum, null: false

      field :creditable_amount_cents, Integer, null: false

      def item_type
        object.fee_type
      end

      def creditable_amount_cents
        object.total_amount_cents - object.credit_note_items.sum(:amount_cents)
      end
    end
  end
end
