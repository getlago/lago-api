# frozen_string_literal: true

module Resolvers
  class UsageAttributionTypeResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = "usage_attribution_types:view"

    description "Query a single usage attribution type of an organization"

    argument :id, ID, required: true, description: "Uniq ID of the usage attribution type"

    type Types::UsageAttributionTypes::Object, null: true

    def resolve(id:)
      raise forbidden_error(code: "feature_unavailable") unless current_organization.account_tree_enabled?

      current_organization.usage_attribution_types.find(id)
    rescue ActiveRecord::RecordNotFound
      not_found_error(resource: "usage_attribution_type")
    end
  end
end
