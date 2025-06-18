# frozen_string_literal: true

class UpdateFixedChargeFields < ActiveRecord::Migration[8.0]
  def change
    add_column :fixed_charges, :units, :integer, default: 1
    safety_assured do
      remove_column :fixed_charges, :untis
      remove_column :fixed_charges, :billing_period_duration
      remove_column :fixed_charges, :billing_period_duration_unit
      remove_column :fixed_charges, :trial_period
      remove_column :fixed_charges, :recurring
      remove_column :fixed_charges, :interval
    end
  end
end
