# frozen_string_literal: true

module Resolvers
  module Entitlement
    class SubscriptionEntitlementsResolver < Resolvers::BaseResolver
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "subscriptions:view"

      description "Query subscription entitlements"

      argument :subscription_external_id, String, required: true

      type [Types::Entitlement::SubscriptionEntitlementObject], null: false

      def resolve(subscription_external_id:)
        raise forbidden_error(code: "feature_unavailable") unless License.premium?

        # Get entitlements for the subscription
        entitlements = current_organization.entitlements
          .where(subscription_external_id: subscription_external_id)
          .includes(:feature, :values)

        # Get removed features for the subscription
        removed_features = current_organization.subscription_feature_removals
          .where(subscription_external_id: subscription_external_id)
          .includes(:feature)

        # Convert entitlements to objects with removed: false
        entitlement_objects = entitlements.map do |entitlement|
          entitlement.define_singleton_method(:removed) { false }
          entitlement
        end

        # Convert removed features to entitlement-like objects with removed: true
        removed_objects = removed_features.map do |removal|
          # Create a pseudo-entitlement object that looks like an entitlement
          pseudo_entitlement = Object.new
          pseudo_entitlement.define_singleton_method(:feature) { removal.feature }
          pseudo_entitlement.define_singleton_method(:values) { [] }
          pseudo_entitlement.define_singleton_method(:removed) { true }
          pseudo_entitlement
        end

        # Merge both lists
        entitlement_objects + removed_objects
      end
    end
  end
end
