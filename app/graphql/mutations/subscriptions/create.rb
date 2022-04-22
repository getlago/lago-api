# frozen_string_literal: true

module Mutations
  module Subscriptions
    class Create < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      graphql_name 'CreateSubscription'
      description 'Create a new Subscription'

      argument :customer_id, ID, required: true
      argument :plan_id, ID, required: true

      type Types::Subscriptions::Object

      def resolve(**args)
        validate_organization!

        result = SubscriptionsService
          .new
          .create(**args.merge(organization_id: current_organization.id))

        result.success? ? result.subscription : result_error(result)
      end
    end
  end
end
