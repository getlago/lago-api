# frozen_string_literal: true

class AddRatesToBillingCycles < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_reference :billing_cycles, :rate_card_rate, type: :uuid, index: {algorithm: :concurrently}
    add_reference :billing_cycles, :rate_override, type: :uuid, index: {algorithm: :concurrently}
  end
end
