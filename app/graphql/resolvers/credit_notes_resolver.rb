# frozen_string_literal: true

module Resolvers
  class CreditNotesResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = "credit_notes:view"

    description "Query credit notes"

    argument :search_term, String, required: false

    argument :limit, Integer, required: false
    argument :page, Integer, required: false

    argument :amount_from, Integer, required: false
    argument :amount_to, Integer, required: false
    argument :billing_entity_ids, [ID], required: false
    argument :credit_status, [Types::CreditNotes::CreditStatusTypeEnum], required: false
    argument :currency, Types::CurrencyEnum, required: false
    argument :customer_external_id, String, required: false
    argument :customer_id, ID, required: false, description: "Uniq ID of the customer"
    argument :invoice_number, String, required: false
    argument :issuing_date_from, GraphQL::Types::ISO8601Date, required: false
    argument :issuing_date_to, GraphQL::Types::ISO8601Date, required: false
    argument :reason, [Types::CreditNotes::ReasonTypeEnum], required: false
    argument :refund_status, [Types::CreditNotes::RefundStatusTypeEnum], required: false
    argument :self_billed, Boolean, required: false

    type Types::CreditNotes::Object.collection_type, null: false

    FILTER_KEYS = %i[
      amount_from amount_to billing_entity_ids credit_status currency customer_external_id
      customer_id invoice_number issuing_date_from issuing_date_to reason refund_status self_billed
    ].freeze

    def resolve(**args)
      includes = [:customer, :items]

      CreditNotesQuery.call(
        organization: current_organization,
        search_term: args[:search_term],
        includes:,
        filters: args.slice(*FILTER_KEYS),
        pagination: args.slice(:page, :limit)
      ).credit_notes
    end
  end
end
