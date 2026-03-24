# frozen_string_literal: true

module Resolvers
  class InvoiceDraftResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = "invoices:view"

    description "Build a draft of a single Invoice of an organization."

    argument :id, ID, required: true, description: "Uniq ID of the invoice"

    type Types::Invoices::Object, null: true

    def resolve(id:)
      invoice = current_organization.invoices.visible.find(id)
      result = Invoices::DraftService.call(invoice: invoice)
      result.success? ? result.invoice : result_error(result)
    rescue ActiveRecord::RecordNotFound
      not_found_error(resource: "invoice")
    end
  end
end
