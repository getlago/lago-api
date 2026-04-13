# frozen_string_literal: true

class CreateSubscriptionRateScheduleCycles < ActiveRecord::Migration[8.0]
  def change
    create_table :subscription_rate_schedule_cycles, id: :uuid do |t|
      t.references :organization, null: false, foreign_key: true, type: :uuid
      t.references :subscription_rate_schedule, null: false, foreign_key: true, type: :uuid,
        index: {name: "idx_srs_cycles_on_subscription_rate_schedule_id"}
      t.integer :cycle_index, null: false
      t.datetime :from_datetime, null: false
      t.datetime :to_datetime, null: false

      t.timestamps

      t.index [:subscription_rate_schedule_id, :cycle_index],
        unique: true,
        name: "idx_srs_cycles_on_srs_id_and_cycle_index"
      t.index :from_datetime, name: "idx_srs_cycles_on_from_datetime"
      t.index :to_datetime, name: "idx_srs_cycles_on_to_datetime"
    end
  end
end
