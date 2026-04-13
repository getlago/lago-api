# frozen_string_literal: true

class CreateSubscriptionRateSchedules < ActiveRecord::Migration[8.0]
  def change
    create_enum :subscription_rate_schedule_status, %w[pending active terminated]

    create_table :subscription_rate_schedules, id: :uuid do |t|
      t.references :organization, null: false, foreign_key: true, type: :uuid
      t.references :subscription, null: false, foreign_key: true, type: :uuid
      t.references :product_item, null: false, foreign_key: true, type: :uuid
      t.references :rate_schedule, null: false, foreign_key: true, type: :uuid

      t.enum :status, enum_type: :subscription_rate_schedule_status, null: false
      t.integer :intervals_to_bill
      t.integer :intervals_billed, null: false, default: 0

      t.datetime :started_at
      t.datetime :ended_at
      t.timestamps
    end
  end
end
