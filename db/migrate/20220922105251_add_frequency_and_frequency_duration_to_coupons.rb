# frozen_string_literal: true

class AddFrequencyAndFrequencyDurationToCoupons < ActiveRecord::Migration[7.0]
  def change
    change_table :coupons, bulk: true do |t|
      t.integer :frequency, null: false, default: 0
      t.integer :frequency_duration
    end

    change_table :applied_coupons, bulk: true do |t|
      t.integer :frequency, null: false, default: 0
      t.integer :frequency_duration
    end
  end
end
