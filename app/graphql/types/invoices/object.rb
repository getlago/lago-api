# frozen_string_literal: true

module Types
  module Invoices
    class Object < Types::BaseObject
      graphql_name 'Invoice'

      field :customer, Types::Customers::Object, null: false

      field :id, ID, null: false
      field :sequential_id, ID, null: false
      field :number, String, null: false
      field :charge_amount_cents, Integer, null: false
      field :amount_cents, Integer, null: false
      field :amount_currency, Types::CurrencyEnum, null: false
      field :vat_amount_cents, Integer, null: false
      field :vat_amount_currency, Types::CurrencyEnum, null: false
      field :credit_amount_cents, Integer, null: false
      field :credit_amount_currency, Types::CurrencyEnum, null: false
      field :total_amount_cents, Integer, null: false
      field :total_amount_currency, Types::CurrencyEnum, null: false
      field :invoice_type, Types::Invoices::InvoiceTypeEnum, null: false
      field :payment_status, Types::Invoices::PaymentStatusTypeEnum, null: false
      field :file_url, String, null: true
      field :vat_rate, Float, null: false

      field :issuing_date, GraphQL::Types::ISO8601Date, null: false

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false

      field :legacy, Boolean, null: false

      field :subscriptions, [Types::Subscriptions::Object]
      field :invoice_subscriptions, [Types::InvoiceSubscription::Object]
      field :fees, [Types::Fees::Object], null: true
      field :plan, Types::Plans::Object
      field :credit_notes, [Types::CreditNotes::Object], null: true

      field :wallet_transaction_amount_cents, Integer, null: false
      field :subtotal_before_prepaid_credits, String, null: false

      field :sub_total_vat_excluded_amount_cents, Integer, null: false
      field :sub_total_vat_included_amount_cents, Integer, null: false
      field :coupon_total_amount_cents, Integer, null: false
      field :credit_note_total_amount_cents, Integer, null: false

      field :refundable_amount_cents, Integer, null: false
      field :creditable_amount_cents, Integer, null: false
    end
  end
end
