# frozen_string_literal: true

module Mutations
  module UsageAttributionTypes
    class Update < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "usage_attribution_types:update"

      graphql_name "UpdateUsageAttributionType"
      description "Updates an existing usage attribution type"

      input_object_class Types::UsageAttributionTypes::UpdateInput
      type Types::UsageAttributionTypes::Object

      def resolve(**args)
        raise forbidden_error(code: "feature_unavailable") unless current_organization.account_tree_enabled?

        usage_attribution_type = current_organization.usage_attribution_types.find_by(id: args[:id])
        result = ::UsageAttributionTypes::UpdateService.call(usage_attribution_type:, params: args.except(:id))

        result.success? ? result.usage_attribution_type : result_error(result)
      end
    end
  end
end
