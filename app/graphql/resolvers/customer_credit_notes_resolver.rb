# frozen_string_literal: true

module Resolvers
  class CustomerCreditNotesResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    description "Query customer's credit note"

    argument :ids, [String], required: false, description: 'List of plan ID to fetch'
    argument :customer_id, ID, required: true, description: 'Uniq ID of the customer'
    argument :page, Integer, required: false
    argument :limit, Integer, required: false

    type Types::CreditNotes::Object.collection_type, null: true

    def resolve(customer_id: nil, ids: nil, page: nil, limit: nil)
      validate_organization!

      current_customer = Customer.find(customer_id)

      credit_notes = current_customer
        .credit_notes
        .finalized
        .order(created_at: :desc)
        .page(page)
        .per(limit)

      credit_notes = credit_notes.where(id: ids) if ids.present?

      credit_notes
    rescue ActiveRecord::RecordNotFound
      not_found_error(resource: 'customer')
    end
  end
end
