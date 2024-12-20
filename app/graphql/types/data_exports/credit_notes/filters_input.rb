# frozen_string_literal: true

module Types
  module DataExports
    module CreditNotes
      class FiltersInput < BaseInputObject
        graphql_name 'DataExportCreditNoteFiltersInput'
        description 'Export credit notes search query and filters input argument'

        argument :amount_from, Integer, required: false
        argument :amount_to, Integer, required: false
        argument :credit_status, [Types::CreditNotes::CreditStatusTypeEnum], required: false
        argument :currency, Types::CurrencyEnum, required: false
        argument :customer_external_id, String, required: false
        argument :customer_id, ID, required: false, description: 'Uniq ID of the customer'
        argument :invoice_number, String, required: false
        argument :issuing_date_from, GraphQL::Types::ISO8601Date, required: false
        argument :issuing_date_to, GraphQL::Types::ISO8601Date, required: false
        argument :reason, [Types::CreditNotes::ReasonTypeEnum], required: false
        argument :refund_status, [Types::CreditNotes::RefundStatusTypeEnum], required: false
        argument :search_term, String, required: false
      end
    end
  end
end
