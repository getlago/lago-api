# frozen_string_literal: true

module Mutations
  module Plans
    class Create < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      graphql_name 'CreatePlan'
      description 'Creates a new Plan'

      argument :amount_cents, GraphQL::Types::BigInt, required: true
      argument :amount_currency, Types::CurrencyEnum
      argument :bill_charges_monthly, Boolean, required: false
      argument :code, String, required: true
      argument :description, String, required: false
      argument :interval, Types::Plans::IntervalEnum, required: true
      argument :name, String, required: true
      argument :parent_id, ID, required: false
      argument :pay_in_advance, Boolean, required: true
      argument :trial_period, Float, required: false

      argument :charges, [Types::Charges::Input]

      type Types::Plans::Object

      def resolve(**args)
        validate_organization!
        args[:charges].map!(&:to_h)

        result = ::Plans::CreateService
          .new(context[:current_user])
          .create(**args.merge(organization_id: current_organization.id))

        result.success? ? result.plan : result_error(result)
      end
    end
  end
end
