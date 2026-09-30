# frozen_string_literal: true

module Resolvers
  class UsageAttributionTypesResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = "usage_attribution_types:view"

    description "Query usage attribution types of an organization"

    argument :limit, Integer, required: false
    argument :page, Integer, required: false
    argument :role, Types::UsageAttributionTypes::RoleEnum, required: false
    argument :roots, Boolean, required: false, description: "Return only root types, each carrying its descendants through `children`"
    argument :search_term, String, required: false

    type Types::UsageAttributionTypes::Object.collection_type, null: false

    def resolve(**args)
      raise forbidden_error(code: "feature_unavailable") unless current_organization.account_tree_enabled?

      result = ::UsageAttributionTypesQuery.call(
        organization: current_organization,
        search_term: args[:search_term],
        pagination: {page: args[:page], limit: args[:limit]},
        filters: args.slice(:role, :roots)
      )

      result.success? ? result.usage_attribution_types : result_error(result)
    end
  end
end
