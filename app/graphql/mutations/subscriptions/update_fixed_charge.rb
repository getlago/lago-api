# frozen_string_literal: true

module Mutations
  module Subscriptions
    class UpdateFixedCharge < BaseMutation
      include AuthenticableApiUser

      REQUIRED_PERMISSION = "subscriptions:update"

      graphql_name "UpdateSubscriptionFixedCharge"
      description "Update a fixed charge for a subscription"

      input_object_class Types::Subscriptions::UpdateFixedChargeInput

      type Types::FixedCharges::Object

      def resolve(**args)
        subscription = context[:current_user].subscriptions.find_by(id: args[:subscription_id])
        fixed_charge = subscription&.plan&.fixed_charges&.find_by(code: args[:fixed_charge_code])

        result = ::Subscriptions::UpdateOrOverrideFixedChargeService.call(
          subscription:,
          fixed_charge:,
          params: args.except(:subscription_id, :fixed_charge_code)
        )

        result.success? ? result.fixed_charge : result_error(result)
      end
    end
  end
end
