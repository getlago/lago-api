# frozen_string_literal: true

module Mutations
  module Subscriptions
    class UpdateCharge < BaseMutation
      include AuthenticableApiUser

      REQUIRED_PERMISSION = "subscriptions:update"

      graphql_name "UpdateSubscriptionCharge"
      description "Update a charge for a subscription"

      input_object_class Types::Subscriptions::UpdateChargeInput

      type Types::Charges::Object

      def resolve(**args)
        subscription = context[:current_user].subscriptions.find_by(id: args[:subscription_id])
        charge = subscription&.plan&.charges&.find_by(code: args[:charge_code])

        result = ::Subscriptions::UpdateOrOverrideChargeService.call(
          subscription:,
          charge:,
          params: args.except(:subscription_id, :charge_code)
        )

        result.success? ? result.charge : result_error(result)
      end
    end
  end
end
