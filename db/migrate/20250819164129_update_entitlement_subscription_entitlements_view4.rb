# frozen_string_literal: true

class UpdateEntitlementSubscriptionEntitlementsView4 < ActiveRecord::Migration[8.0]
  def change
    update_view :entitlement_subscription_entitlements_view, version: 4, revert_to_version: 3
  end
end
