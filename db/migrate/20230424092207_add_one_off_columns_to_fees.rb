# frozen_string_literal: true

class AddOneOffColumnsToFees < ActiveRecord::Migration[7.0]
  def change
    safety_assured do
      change_table :fees, bulk: true do |t|
        t.references :add_on, type: :uuid, null: true, index: true, foreign_key: true
        t.string :description
        t.bigint :unit_amount_cents, null: false, default: 0
      end
    end
  end
end
