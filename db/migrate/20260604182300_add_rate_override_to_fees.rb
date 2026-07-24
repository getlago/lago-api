# frozen_string_literal: true

class AddRateOverrideToFees < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_reference :fees, :rate_override, type: :uuid, null: true, index: {algorithm: :concurrently}
    add_foreign_key :fees, :rate_overrides, column: :rate_override_id, validate: false
  end
end
