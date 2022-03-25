# frozen_string_literal: true

module Mutations
  module Plans
    class Create < BaseMutation
      include AuthenticableApiUser

      graphql_name 'CreatePlan'
      description 'Creates a new Plan'

      argument :organization_id, String, required: true
      argument :name, String, required: true
      argument :code, String, required: true
      argument :frequency, Types::Plans::FrequencyEnum, required: true
      argument :billing_period, Types::Plans::BillingPeriodEnum, required: true
      argument :pro_rata, Boolean, required: true
      argument :amount_cents, Integer, required: true
      argument :amount_currency, Types::CurrencyEnum
      argument :vat_rate, Float, required: false
      argument :trial_period, Float, required: false
      argument :description, String, required: false

      argument :charges, [Types::Charges::Input]

      type Types::Plans::Object

      def resolve(**args)
        result = PlansService.new(context[:current_user]).create(**args)

        result.success? ? result.plan : execution_error(code: result.error_code, message: result.error)
      end
    end
  end
end
