# frozen_string_literal: true

class SubscriptionEntitlement < ApplicationRecord
  self.table_name = "subscription_entitlements_view"

  belongs_to :feature
  belongs_to :privilege

  def self.for_subscription(subscription)
    where(subscription_external_id: subscription.external_id)
      .or(where(plan_id: subscription.plan.parent_id || subscription.plan.id))
  end

  def readonly?
    true
  end
end

# == Schema Information
#
# Table name: subscription_entitlements_view
#
#  privilege_override_value :string
#  privilege_plan_value     :string
#  removed                  :boolean
#  feature_entitlement_id   :uuid
#  feature_id               :uuid
#  plan_id                  :uuid
#  privilege_id             :uuid
#  subscription_external_id :string
#
