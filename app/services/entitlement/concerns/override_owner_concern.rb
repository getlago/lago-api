# frozen_string_literal: true

module Entitlement
  module Concerns
    # The record whose entitlement rows override those of its plan: a subscription.
    module OverrideOwnerConcern
      extend ActiveSupport::Concern

      private

      # The owner column of entitlement and removal rows, as an association name.
      def override_owner_key(owner)
        case owner
        when ::Subscription then :subscription
        else raise ArgumentError, "unknown entitlement override owner: #{owner.class}"
        end
      end

      # The entitlements of the plan that the owner overrides.
      def owner_plan_entitlements(owner)
        ::Entitlement::Entitlement.where(plan_id: owner.plan.parent_id || owner.plan.id)
      end

      # update_all skips the callbacks, so it sets updated_at itself.
      def discarded_columns
        now = Time.current
        {deleted_at: now, updated_at: now}
      end
    end
  end
end
