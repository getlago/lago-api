# frozen_string_literal: true

class UpdateFixedChargeFields < ActiveRecord::Migration[8.0]
  def change
    add_column :fixed_charges, :units, :integer, default: 1
    safety_assured do
      remove_column :fixed_charges, :untis, :integer, default: 1
      remove_column :fixed_charges, :billing_period_duration, :integer, default: 1
      remove_column :fixed_charges, :billing_period_duration_unit, :string, default: "month"
      remove_column :fixed_charges, :trial_period, :integer, default: 0
      remove_column :fixed_charges, :recurring, :boolean, default: true
      remove_column :fixed_charges, :interval, :string, default: "month"
    end
  end
end
