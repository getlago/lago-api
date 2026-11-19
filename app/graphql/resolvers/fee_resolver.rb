# frozen_string_literal: true

module Resolvers
  class FeeResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = "invoices:view"

    description "Query a single fee of an organization"

    argument :id, ID, required: true, description: "Uniq ID of the fee"

    type Types::Fees::Object, null: true

    def resolve(id:)
      current_organization.fees.find(id)
    rescue ActiveRecord::RecordNotFound
      not_found_error(resource: "fee")
    end
  end
end
