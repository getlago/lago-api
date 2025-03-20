# frozen_string_literal: true

module Resolvers
  class BillingEntitiesResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = "billing_entities:view"

    description "Query active billing_entities of an organization"

    type Types::BillingEntity::Object.collection_type, null: false

    def resolve(_args)
      organization.billing_entities
    end
  end
end
