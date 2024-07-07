module Types
  module DataExports
    module Invoices
      class FiltersInput < BaseInputObject
        description 'Export Invoices search query and filters input argument'

        argument :currency, Types::CurrencyEnum, required: false
        argument :customer_external_id, String, required: false
        argument :invoice_type, Types::Invoices::InvoiceTypeEnum, required: false
        argument :issuing_date_from, GraphQL::Types::ISO8601Date, required: false
        argument :issuing_date_to, GraphQL::Types::ISO8601Date, required: false
        argument :payment_dispute_lost, Boolean, required: false
        argument :payment_overdue, Boolean, required: false
        argument :payment_status, [Types::Invoices::PaymentStatusTypeEnum], required: false
        argument :search_term, String, required: false
        argument :status, Types::Invoices::StatusTypeEnum, required: false
      end
    end
  end
end
