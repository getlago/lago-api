# frozen_string_literal: true

module Mutations
  module WebhookEndpoints
    class Create < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      graphql_name 'CreateWebhookEndpoint'
      description 'Create a new webhook endpoint'

      input_object_class Types::WebhookEndpoints::CreateInput

      type Types::WebhookEndpoints::Object

      def resolve(**args)
        validate_organization!

        result = ::WebhookEndpoints::CreateService.call(
          organization: current_organization,
          params: args,
        )
        result.success? ? result.webhook_endpoint : result_error(result)
      end
    end
  end
end
