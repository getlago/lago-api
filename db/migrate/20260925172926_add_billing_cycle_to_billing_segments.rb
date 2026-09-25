# frozen_string_literal: true

class AddBillingCycleToBillingSegments < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    # Historical rows keep working while the engine moves to explicit cycles.
    add_reference :billing_segments, :billing_cycle, type: :uuid, null: true,
      index: {algorithm: :concurrently}
    add_foreign_key :billing_segments, :billing_cycles, validate: false
  end
end
