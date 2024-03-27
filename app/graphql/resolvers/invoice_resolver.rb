# frozen_string_literal: true

module Resolvers
  class InvoiceResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    description "Query a single Invoice of an organization"

    argument :id, ID, required: true, description: "Uniq ID of the invoice"

    type Types::Invoices::Object, null: true

    def resolve(id:)
      validate_organization!

      current_organization.invoices.not_generating.find(id)
    rescue ActiveRecord::RecordNotFound
      not_found_error(resource: "invoice")
    end
  end
end
