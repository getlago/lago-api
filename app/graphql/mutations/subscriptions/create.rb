# frozen_string_literal: true

module Mutations
  module Subscriptions
    class Create < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      graphql_name 'CreateSubscription'
      description 'Create a new Subscription'

      argument :customer_id, String, required: true
      argument :plan_code, String, required: true

      type Types::Subscriptions::Object

      def resolve(**args)
        validate_organization!

        result = SubscriptionsService
          .new
          .create(
            organization: current_organization,
            params: args,
          )
        
          result.success? ? result.subscription : execution_error(code: result.error_code, message: result.error)
      end
    end
  end
end
