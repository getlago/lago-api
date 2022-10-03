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
      argument :name, String, required: false
      argument :subscription_id, ID, required: false
      argument :billing_time, Types::Subscriptions::BillingTimeEnum, required: true
      argument :subscription_date, GraphQL::Types::ISO8601Date, required: false

      type Types::Subscriptions::Object

      def resolve(**args)
        validate_organization!

        result = ::Subscriptions::CreateService
          .new
          .create(**args.merge(organization_id: current_organization.id))

        result.success? ? result.subscription : result_error(result)
      end
    end
  end
end
