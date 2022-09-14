# frozen_string_literal: true

module Mutations
  module Subscriptions
    class CreateWithOverride < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization
      include ChargeModelAttributesHandler

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

        result = ::Subscriptions::CreateWithOverriddenPlanService
          .new(context[:current_user])
          .call(plan_args: prepare_plan_params(args), subscription_args: prepare_subscription_params(args))

        result.success? ? result.subscription : result_error(result)
      end

      private

      def prepare_plan_params(args)
        params = args[:plan].to_h
        params[:code] = "#{params[:code]}-#{SecureRandom.uuid}"

        prepare_arguments(**params)
          .merge(overridden_plan_id: args[:overridden_plan_id])
          .merge(organization_id: current_organization.id)
      end

      def prepare_subscription_params(args)
        args.delete(:plan)
        args.delete(:overridden_plan_id)

        args.merge(organization_id: current_organization.id)
      end
    end
  end
end
