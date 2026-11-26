# frozen_string_literal: true

module Entitlement
  module Concerns
    # The record whose entitlement rows override those of its plan: a subscription, or a contract over its catalog plan.
    module OverrideOwnerConcern
      extend ActiveSupport::Concern

      private

      # The owner column of entitlement and removal rows, as an association name.
      def override_owner_key(owner)
        case owner
        when ::Subscription then :subscription
        when ::Contract then :contract
        else raise ArgumentError, "unknown entitlement override owner: #{owner.class}"
        end
      end

      # The entitlements of the plan that the owner overrides. A contract without a catalog plan has none.
      def owner_plan_entitlements(owner)
        if override_owner_key(owner) == :contract
          return ::Entitlement::Entitlement.none unless owner.catalog_plan_id

          ::Entitlement::Entitlement.where(catalog_plan_id: owner.catalog_plan_id)
        else
          ::Entitlement::Entitlement.where(plan_id: owner.plan.parent_id || owner.plan.id)
        end
      end

      # A contract row without values over a feature that the catalog plan grants changes nothing: it is discarded.
      # Subscriptions keep theirs, as v1 always did.
      def discard_empty_contract_entitlement(owner, entitlement)
        return unless override_owner_key(owner) == :contract
        return if ::Entitlement::EntitlementValue.where(entitlement:).exists?

        entitlement.discard!
      end

      # update_all skips the callbacks, so it sets updated_at itself.
      def discarded_columns
        now = Time.current
        {deleted_at: now, updated_at: now}
      end
    end
  end
end
