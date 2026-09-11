# frozen_string_literal: true

module Mutations
  module UsageAttributionTypes
    class Destroy < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "usage_attribution_types:delete"

      graphql_name "DestroyUsageAttributionType"
      description "Deletes a usage attribution type"

      argument :id, ID, required: true

      field :id, ID, null: true

      def resolve(id:)
        raise forbidden_error(code: "feature_unavailable") unless current_organization.account_tree_enabled?

        usage_attribution_type = current_organization.usage_attribution_types.find_by(id:)
        result = ::UsageAttributionTypes::DestroyService.call(usage_attribution_type:)

        result.success? ? result.usage_attribution_type : result_error(result)
      end
    end
  end
end
