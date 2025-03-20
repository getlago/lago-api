# frozen_string_literal: true

module Resolvers
  class BillingEntityResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = "billing_entity:view"

    description "Query a single billing_entity of an organization"

    argument :id, ID, required: true, description: "Uniq ID of the billing_entity"

    type Types::BillingEntities::Object, null: true

    def resolve(id: nil)
      current_organization.all_billing_entities.find(id)
    rescue ActiveRecord::RecordNotFound
      not_found_error(resource: "billing_entity")
    end
  end
end
