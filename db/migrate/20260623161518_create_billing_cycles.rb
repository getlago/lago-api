# frozen_string_literal: true

class CreateBillingCycles < ActiveRecord::Migration[8.0]
  def change
    create_enum :billing_cycle_status, %w[pending processing done failed]

    create_table :billing_cycles, id: :uuid do |t|
      t.references :organization, null: false, foreign_key: true, type: :uuid
      t.references :subscription, null: false, foreign_key: true, type: :uuid
      t.references :subscription_product_item, null: false, foreign_key: true, type: :uuid

      # The instant this cycle becomes billable (the boundary the scheduler picked it
      # up on). Cycles sharing a subscription + billing_at are invoiced together.
      t.datetime :billing_at, null: false

      t.datetime :period_from, null: false
      t.datetime :period_to, null: false

      t.enum :status, enum_type: :billing_cycle_status, null: false, default: "pending"
      t.integer :attempts, null: false, default: 0

      t.timestamps

      # Idempotency backstop: one cycle per (product item, period). A re-pickup is a
      # no-op insert, never a double bill.
      t.index [:subscription_product_item_id, :period_from],
        unique: true,
        name: "index_billing_cycles_on_product_item_and_period"

      # Processor: find a subscription's pending cycles for a billing moment.
      t.index [:subscription_id, :billing_at, :status]
    end
  end
end
