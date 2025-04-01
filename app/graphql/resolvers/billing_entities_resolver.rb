# frozen_string_literal: true

module Resolvers
  class BillingEntitiesResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = "billing_entities:view"

    description "Query active billing_entities of an organization"

    type Types::BillingEntities::Object.collection_type, null: false

    def resolve(**args)
      BillingEntity.active.where(organization: current_organization)
    end
  end
end
