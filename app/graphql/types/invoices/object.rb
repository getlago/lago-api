# frozen_string_literal: true

module Types
  module Invoices
    class Object < Types::BaseObject
      graphql_name 'Invoice'

      field :id, ID, null: false
      field :sequential_id, ID, null: false
      field :number, String, null: false
      field :amount_cents, Integer, null: false
      field :amount_currency, Types::CurrencyEnum, null: false
      field :total_amount_cents, Integer, null: false
      field :total_amount_currency, Types::CurrencyEnum, null: false
      field :vat_amount_cents, Integer, null: false
      field :vat_amount_currency, Types::CurrencyEnum, null: false
      field :invoice_type, Types::Invoices::InvoiceTypeEnum, null: false
      field :status, Types::Invoices::StatusTypeEnum, null: false
      field :file_url, String, null: true

      field :issuing_date, GraphQL::Types::ISO8601Date, null: false

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false

      field :subscription, Types::Subscriptions::Object
      field :plan, Types::Plans::Object
    end
  end
end
