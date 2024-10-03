# frozen_string_literal: true

class AddValueToEvents < ActiveRecord::Migration[7.1]
  def change
    safety_assured do
      change_table :events, bulk: true do |t|
        t.decimal :value_numeric, precision: 40, scale: 15
        t.string :value
      end
    end
  end
end
