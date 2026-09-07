# frozen_string_literal: true

class AddPricingTypeToPlans < ActiveRecord::Migration[8.0]
  def change
    create_enum :plan_pricing_type, %w[legacy product_catalog]
    add_column :plans, :pricing_type, :enum, enum_type: :plan_pricing_type, default: "legacy", null: false

    safety_assured do
      change_column_null :plans, :interval, true
      change_column_null :plans, :amount_cents, true
      change_column_null :plans, :pay_in_advance, true
    end
  end
end
