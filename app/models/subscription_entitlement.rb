# frozen_string_literal: true

class SubscriptionEntitlement < ApplicationRecord
  self.table_name = "subscription_entitlements_view"

  belongs_to :feature
  belongs_to :privilege

  scope :for_subscription, ->(sub) do
    where(subscription_external_id: sub.external_id)
      .or(where(plan_id: sub.plan.parent_id || sub.plan.id))
  end

  def readonly?
    true
  end

  def privilege_value_casted
    privilege_override_value_casted || privilege_plan_value_casted
  end

  def privilege_plan_value_casted
    cast_value(privilege_plan_value, privilege_value_type)
  end

  def privilege_override_value_casted
    cast_value(privilege_override_value, privilege_value_type)
  end

  private

  def cast_value(raw_value, type)
    return nil if raw_value.nil?

    case type
    when "integer"
      raw_value.to_i
    when "boolean"
      ActiveModel::Type::Boolean.new.cast(raw_value)
    else
      raw_value.to_s
    end
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
