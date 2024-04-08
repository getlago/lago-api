# frozen_string_literal: true

module Mutations
  module Subscriptions
    class Terminate < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      graphql_name 'TerminateSubscription'
      description 'Terminate a Subscription'

      argument :id, ID, required: true

      type Types::Subscriptions::Object

      def resolve(**args)
        subscription = current_organization.subscriptions.find_by(id: args[:id])
        result = ::Subscriptions::TerminateService.call(subscription:)

        result.success? ? result.subscription : result_error(result)
      end
    end
  end
end
