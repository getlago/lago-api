# frozen_string_literal: true

class PrivilegeWithValue
  include ActiveModel::Model

  attr_accessor :privilege, :value, :plan_value, :override_value

  delegate :name, :code, :value_type, to: :privilege

  def initialize(privilege:, plan_value:, override_value:)
    @privilege = privilege
    @value = override_value || plan_value
    @plan_value = plan_value
    @override_value = override_value
  end

  def value_casted
    cast_value(value, value_type)
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
