# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Resolvers
  class BillingEntitiesResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = "billing_entities:view"

    description "Query active billing_entities of an organization"

    type Types::BillingEntities::Object.collection_type, null: false

    def resolve(**args)
      current_organization.billing_entities
    end
  end
end
