# frozen_string_literal: true

module Mutations
  module Subscriptions
    class Update < BaseMutation
      include AuthenticableApiUser

      graphql_name 'UpdateSubscription'
      description 'Update a Subscription'

      argument :id, ID, required: true
      argument :name, String, required: false
      argument :subscription_date, GraphQL::Types::ISO8601Date, required: false

      type Types::Subscriptions::Object

      def resolve(**args)
        result = ::Subscriptions::UpdateService
          .new(context[:current_user])
          .update(**args)

        result.success? ? result.subscription : result_error(result)
      end
    end
  end
end
