# frozen_string_literal: true

module Resolvers
  class CreditNotesResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = 'credit_notes:view'

    description 'Query credit notes'

    argument :customer_id, ID, required: false
    argument :limit, Integer, required: false
    argument :page, Integer, required: false
    argument :search_term, String, required: false

    type Types::CreditNotes::Object.collection_type, null: false

    def resolve(
      page: nil,
      limit: nil,
      search_term: nil,
      customer_id: nil
    )
      result = CreditNotesQuery.call(
        organization: current_organization,
        search_term:,
        filters: {
          customer_id:
        },
        pagination: {
          page:,
          limit:
        }
      )

      result.credit_notes
    end
  end
end
