# frozen_string_literal: true

module Mutations
  module Plans
    class Update < BaseMutation
      include AuthenticableApiUser

      REQUIRED_PERMISSION = 'plans:update'

      graphql_name 'UpdatePlan'
      description 'Updates an existing Plan'

      argument :amount_cents, GraphQL::Types::BigInt, required: true
      argument :amount_currency, Types::CurrencyEnum, required: true
      argument :bill_charges_monthly, Boolean, required: false
      argument :cascade_updates, Boolean, required: false
      argument :code, String, required: true
      argument :description, String, required: false
      argument :id, String, required: true
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
        plan = context[:current_user].plans.find_by(id: args[:id])

        result = ::Plans::UpdateService.call(plan:, params: args)
        result.success? ? result.plan : result_error(result)
      end
    end
  end
end
