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

  def privilege_plan_value_casted
    cast_value(privilege_plan_value, value_type)
  end

  def privilege_override_value_casted
    cast_value(privilege_override_value, value_type)
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
#  privilege_override_value :string
#  privilege_plan_value     :string
#  removed                  :boolean
#  feature_entitlement_id   :uuid
#  feature_id               :uuid
#  plan_id                  :uuid
#  privilege_id             :uuid
#  subscription_external_id :string
#
