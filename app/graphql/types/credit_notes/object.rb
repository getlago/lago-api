# frozen_string_literal: true

module Types
  module CreditNotes
    class Object < Types::BaseObject
      description "CreditNote"
      graphql_name "CreditNote"

      field :id, ID, null: false
      field :number, String, null: false
      field :sequential_id, ID, null: false

      field :issuing_date, GraphQL::Types::ISO8601Date, null: false

      field :description, String, null: true
      field :reason, Types::CreditNotes::ReasonTypeEnum, null: false

      field :credit_status, Types::CreditNotes::CreditStatusTypeEnum, null: true
      field :refund_status, Types::CreditNotes::RefundStatusTypeEnum, null: true

      field :currency, Types::CurrencyEnum, null: false
      field :taxes_rate, Float, null: false

      field :balance_amount_cents, GraphQL::Types::BigInt, null: false
      field :coupons_adjustment_amount_cents, GraphQL::Types::BigInt, null: false
      field :credit_amount_cents, GraphQL::Types::BigInt, null: false
      field :refund_amount_cents, GraphQL::Types::BigInt, null: false
      field :sub_total_excluding_taxes_amount_cents, GraphQL::Types::BigInt, null: false
      field :taxes_amount_cents, GraphQL::Types::BigInt, null: false
      field :total_amount_cents, GraphQL::Types::BigInt, null: false

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :refunded_at, GraphQL::Types::ISO8601DateTime, null: true
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false
      field :voided_at, GraphQL::Types::ISO8601DateTime, null: true

      field :file_url, String, null: true

      field :applied_taxes, [Types::CreditNotes::AppliedTaxes::Object]
      field :customer, Types::Customers::Object, null: false
      field :invoice, Types::Invoices::Object
      field :items, [Types::CreditNoteItems::Object], null: false

      field :can_be_voided, Boolean, null: false, method: :voidable? do
        description "Check if credit note can be voided"
      end

      def applied_taxes
        object.applied_taxes.order(tax_rate: :desc)
      end
    end
  end
end
