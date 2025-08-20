# frozen_string_literal: true

class UpdateEntitlementSubscriptionEntitlementsView3 < ActiveRecord::Migration[8.0]
  def change
    update_view :entitlement_subscription_entitlements_view, version: 3, revert_to_version: 2
  end
end
