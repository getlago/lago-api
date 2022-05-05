# frozen_string_literal: true

module Mutations
  module Plans
    class Create < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      graphql_name 'CreatePlan'
      description 'Creates a new Plan'

      argument :name, String, required: true
      argument :code, String, required: true
      argument :interval, Types::Plans::IntervalEnum, required: true
      argument :pay_in_advance, Boolean, required: true
      argument :amount_cents, Integer, required: true
      argument :amount_currency, Types::CurrencyEnum
      argument :trial_period, Float, required: false
      argument :description, String, required: false

      argument :charges, [Types::Charges::Input]

      type Types::Plans::Object

      def resolve(**args)
        validate_organization!

        result = PlansService
          .new(context[:current_user])
          .create(**prepare_arguments(**args))

        result.success? ? result.plan : result_error(result)
      end

      def prepare_arguments(arguments)
        result = arguments.merge(organization_id: current_organization.id)

        if result[:charges].present?
          result[:charges].map! do |charge|
            output = charge.to_h
            output[:properties] = output[:graduated_ranges]
            output.delete(:graduated_ranges)
            output
          end
        end

        result
      end
    end
  end
end
