# frozen_string_literal: true

module Mutations
  module Subscriptions
    class CreateWithOverride < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      graphql_name 'CreateSubscriptionWithOverride'
      description 'Create a new Subscription from parent plan'

      argument :customer_id, ID, required: true
      argument :overridden_plan_id, ID, required: true
      argument :name, String, required: false
      argument :subscription_id, ID, required: false
      argument :billing_time, Types::Subscriptions::BillingTimeEnum, required: true

      argument :plan, Types::Plans::Input, required: true

      type Types::Subscriptions::Object

      def resolve(**args)
        validate_organization!

        result = ::Subscriptions::OverrideService
          .new(context[:current_user])
          .call(**prepare_params(args))

        result.success? ? result.subscription : result_error(result)
      end

      private

      def prepare_params(args)
        args[:plan] = args[:plan].to_h

        args.merge(organization_id: current_organization.id)
      end
    end
  end
end
