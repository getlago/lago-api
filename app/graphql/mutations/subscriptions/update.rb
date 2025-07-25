# frozen_string_literal: true

module Mutations
  module Subscriptions
    class Update < BaseMutation
      include AuthenticableApiUser

      REQUIRED_PERMISSION = "subscriptions:update"

      graphql_name "UpdateSubscription"
      description "Update a Subscription"

      input_object_class Types::Subscriptions::UpdateSubscriptionInput

      type Types::Subscriptions::Object

      def resolve(entitlements: nil, **args)
        subscription = context[:current_user].subscriptions.find_by(id: args[:id])
        result = ::Subscriptions::UpdateService.call(subscription:, params: args)

        if entitlements.present? && License.premium?
          result = ::Entitlement::SubscriptionEntitlementsUpdateService.call(
            organization: subscription.organization,
            subscription:,
            entitlements_params: entitlements.map do |ent|
              [
                ent.feature_code,
                ent.privileges&.map { [it.privilege_code, it.value] }.to_h
              ]
            end.to_h,
            partial: false
          )
        end

        result.success? ? subscription.reload : result_error(result)
      end
    end
  end
end
