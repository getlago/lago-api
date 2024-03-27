# frozen_string_literal: true

module Mutations
  module Subscriptions
    class Update < BaseMutation
      include AuthenticableApiUser

      graphql_name "UpdateSubscription"
      description "Update a Subscription"

      input_object_class Types::Subscriptions::UpdateSubscriptionInput

      type Types::Subscriptions::Object

      def resolve(**args)
        subscription = context[:current_user].subscriptions.find_by(id: args[:id])
        result = ::Subscriptions::UpdateService.call(subscription:, params: args)

        result.success? ? result.subscription : result_error(result)
      end
    end
  end
end
