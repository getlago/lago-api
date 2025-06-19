# frozen_string_literal: true

class Entitlement < ApplicationRecord
  self.table_name = "entitlements_view"

  belongs_to :feature

  def readonly?
    true
  end

  def plan_value_casted
    cast_value(plan_value, value_type)
  end

  def override_value_casted
    cast_value(override_value, value_type)
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
# Table name: entitlements_view
#
#  privilege_code           :string
#  privilege_name           :string
#  privilege_override_value :string
#  privilege_plan_value     :string
#  privilege_value_type     :string
#  feature_entitlement_id   :uuid
#  feature_id               :uuid
#  plan_id                  :uuid
#  privilege_id             :uuid
#  subscription_external_id :string
#
