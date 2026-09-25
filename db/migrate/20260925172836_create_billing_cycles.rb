# frozen_string_literal: true

class CreateBillingCycles < ActiveRecord::Migration[8.0]
  def change
    create_table :billing_cycles, id: :uuid do |t|
      t.references :organization, type: :uuid, null: false, foreign_key: true
      t.references :contract_rate_card, type: :uuid, null: false, foreign_key: true, index: false

      t.integer :cycle_index, null: false
      t.datetime :started_at, null: false
      t.datetime :ended_at, null: false
      t.datetime :reference_started_at, null: false
      t.string :timezone, null: false

      t.timestamps

      t.index [:contract_rate_card_id, :cycle_index], unique: true
      t.index [:contract_rate_card_id, :started_at], unique: true
      t.check_constraint "cycle_index >= 0", name: "billing_cycles_nonnegative_index"
      t.check_constraint "reference_started_at <= started_at AND started_at < ended_at",
        name: "billing_cycles_period_bounds"
    end
  end
end
