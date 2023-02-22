# frozen_string_literal: true

module Mutations
  module Webhooks
    class Resend < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      graphql_name 'ResendWebhook'
      description 'Resend a Webhook'

      argument :id, ID, required: true

      type Types::Webhooks::Object

      def resolve(id:)
        validate_organization!

        webhook = current_organization.webhooks.find_by(id:)
        result = ::Webhooks::ResendService.new(webhook:).call

        result.success? ? result.webhook : result_error(result)
      end
    end
  end
end
