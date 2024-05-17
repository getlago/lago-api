# frozen_string_literal: true

module Resolvers
  class CustomerCreditNotesResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = 'customers:view'

    description "Query customer's credit note"

    argument :customer_id, ID, required: true, description: 'Uniq ID of the customer'
    argument :ids, [String], required: false, description: 'List of plan ID to fetch'
    argument :limit, Integer, required: false
    argument :page, Integer, required: false
    argument :search_term, String, required: false

    type Types::CreditNotes::Object.collection_type, null: true

    def resolve(customer_id: nil, ids: nil, page: nil, limit: nil, search_term: nil)
      query = CustomerCreditNotesQuery.new(organization: current_organization)
      result = query.call(
        search_term:,
        page:,
        customer_id:,
        limit:,
        filters: {
          ids:
        },
      )

      result.credit_notes
    rescue ActiveRecord::RecordNotFound
      not_found_error(resource: 'customer')
    end
  end
end
