# frozen_string_literal: true

module Mutations
  module Webhooks
    class Retry < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      graphql_name "RetryWebhook"
      description "Retry a Webhook"

      argument :id, ID, required: true

      type Types::Webhooks::Object

      def resolve(id:)
        validate_organization!

        webhook = current_organization.webhooks.find_by(id:)
        result = ::Webhooks::RetryService.call(webhook:)

        result.success? ? result.webhook : result_error(result)
      end
    end
  end
end
