# frozen_string_literal: true

module Resolvers
  class InvoiceResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = "invoices:view"

    description "Query a single Invoice of an organization"

    argument :id, ID, required: true, description: "Uniq ID of the invoice"

    type Types::Invoices::Object, null: true

    def resolve(id:)
      invoice = current_organization.invoices.visible.find(id)
      context.scoped_set!(:invoice_detail, true)
      invoice
    rescue ActiveRecord::RecordNotFound
      not_found_error(resource: "invoice")
    end
  end
end
