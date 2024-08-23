# frozen_string_literal: true

class AddMultipleValuesToChargeFilterValues < ActiveRecord::Migration[7.0]
  def up
    safety_assured do
      change_table :charge_filter_values, bulk: true do |t|
        t.remove :value
        t.string :values, array: true, default: [], null: false
      end
    end
  end

  def down
    change_table :charge_filter_values, bulk: true do |t|
      t.remove :values
      t.string :value, null: false
    end
  end
end
