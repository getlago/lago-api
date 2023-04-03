# frozen_string_literal: true

module Mutations
  module Subscriptions
    class Create < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      graphql_name 'CreateSubscription'
      description 'Create a new Subscription'

      input_object_class Types::Subscriptions::CreateSubscriptionInput

      type Types::Subscriptions::Object

      def resolve(**args)
        validate_organization!

        customer = Customer.find_by(
          id: args[:customer_id],
          organization_id: current_organization.id,
        )

        plan = Plan.find_by(
          id: args[:plan_id],
          organization_id: current_organization.id,
        )

        result = ::Subscriptions::CreateService.call(
          customer:,
          plan:,
          params: args.merge(external_id: args[:external_id] || SecureRandom.uuid),
        )

        result.success? ? result.subscription : result_error(result)
      end
    end
  end
end
