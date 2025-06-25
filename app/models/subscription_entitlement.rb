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
#  feature_code                           :string
#  feature_deleted_at                     :datetime
#  feature_description                    :text
#  feature_name                           :string
#  privilege_code                         :string
#  privilege_config                       :jsonb
#  privilege_deleted_at                   :datetime
#  privilege_name                         :string
#  privilege_override_value               :string
#  privilege_plan_value                   :string
#  privilege_value_type                   :string
#  removed                                :boolean
#  feature_id                             :uuid
#  organization_id                        :uuid
#  override_feature_entitlement_id        :uuid
#  override_feature_entitlement_values_id :uuid
#  plan_feature_entitlement_id            :uuid
#  plan_feature_entitlement_values_id     :uuid
#  plan_id                                :uuid
#  privilege_id                           :uuid
#  subscription_external_id               :string
#
