# frozen_string_literal: true

class RemoveAmountCurrencyFromUsageTresholds < ActiveRecord::Migration[7.1]
  def up
    change_table :usage_thresholds, bulk: true do |t|
      t.remove :amount_currency
    end
  end

  def down
    change_table :usage_thresholds, bulk: true do |t|
      t.string :amount_currency, null: false
    end
  end
end
