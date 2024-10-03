# frozen_string_literal: true

module Mutations
  module Plans
    class Create < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = 'plans:create'

      graphql_name 'CreatePlan'
      description 'Creates a new Plan'

      argument :amount_cents, GraphQL::Types::BigInt, required: true
      argument :amount_currency, Types::CurrencyEnum
      argument :bill_charges_monthly, Boolean, required: false
      argument :code, String, required: true
      argument :description, String, required: false
      argument :interval, Types::Plans::IntervalEnum, required: true
      argument :invoice_display_name, String, required: false
      argument :name, String, required: true
      argument :pay_in_advance, Boolean, required: true
      argument :tax_codes, [String], required: false
      argument :trial_period, Float, required: false

      argument :charges, [Types::Charges::Input]
      argument :minimum_commitment, Types::Commitments::Input, required: false
      argument :usage_thresholds, [Types::UsageThresholds::Input], required: false

      type Types::Plans::Object

      def resolve(**args)
        args[:charges].map!(&:to_h)

        result = ::Plans::CreateService.call(args.merge(organization_id: current_organization.id))

        result.success? ? result.plan : result_error(result)
      end
    end
  end
end
