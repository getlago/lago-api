# frozen_string_literal: true

module Types
  module Invoices
    class Object < Types::BaseObject
      description 'Invoice'
      graphql_name 'Invoice'

      field :customer, Types::Customers::Object, null: false

      field :id, ID, null: false
      field :number, String, null: false
      field :sequential_id, ID, null: false

      field :version_number, Integer, null: false

      field :invoice_type, Types::Invoices::InvoiceTypeEnum, null: false
      field :payment_dispute_losable, Boolean, null: false, method: :payment_dispute_losable?
      field :payment_dispute_lost_at, GraphQL::Types::ISO8601DateTime
      field :payment_status, Types::Invoices::PaymentStatusTypeEnum, null: false
      field :status, Types::Invoices::StatusTypeEnum, null: false
      field :voidable, Boolean, null: false, method: :voidable?

      field :currency, Types::CurrencyEnum
      field :taxes_rate, Float, null: false

      field :charge_amount_cents, GraphQL::Types::BigInt, null: false
      field :coupons_amount_cents, GraphQL::Types::BigInt, null: false
      field :credit_notes_amount_cents, GraphQL::Types::BigInt, null: false
      field :fees_amount_cents, GraphQL::Types::BigInt, null: false
      field :prepaid_credit_amount_cents, GraphQL::Types::BigInt, null: false
      field :sub_total_excluding_taxes_amount_cents, GraphQL::Types::BigInt, null: false
      field :sub_total_including_taxes_amount_cents, GraphQL::Types::BigInt, null: false
      field :taxes_amount_cents, GraphQL::Types::BigInt, null: false
      field :total_amount_cents, GraphQL::Types::BigInt, null: false

      field :issuing_date, GraphQL::Types::ISO8601Date, null: false
      field :payment_due_date, GraphQL::Types::ISO8601Date, null: false

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false

      field :creditable_amount_cents, GraphQL::Types::BigInt, null: false
      field :refundable_amount_cents, GraphQL::Types::BigInt, null: false

      field :file_url, String, null: true
      field :metadata, [Types::Invoices::Metadata::Object], null: true

      field :applied_taxes, [Types::Invoices::AppliedTaxes::Object]
      field :credit_notes, [Types::CreditNotes::Object], null: true
      field :fees, [Types::Fees::Object], null: true
      field :invoice_subscriptions, [Types::InvoiceSubscription::Object]
      field :subscriptions, [Types::Subscriptions::Object]

      def applied_taxes
        object.applied_taxes.order(tax_rate: :desc)
      end
    end
  end
end
