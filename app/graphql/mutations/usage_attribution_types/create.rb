# frozen_string_literal: true

module Mutations
  module UsageAttributionTypes
    class Create < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "usage_attribution_types:create"

      graphql_name "CreateUsageAttributionType"
      description "Creates a new usage attribution type"

      input_object_class Types::UsageAttributionTypes::CreateInput
      type Types::UsageAttributionTypes::Object

      def resolve(**args)
        raise forbidden_error(code: "feature_unavailable") unless current_organization.account_tree_enabled?

        result = ::UsageAttributionTypes::CreateService.call(organization: current_organization, params: args)

        result.success? ? result.usage_attribution_type : result_error(result)
      end
    end
  end
end
