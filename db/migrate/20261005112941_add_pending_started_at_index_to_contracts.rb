# frozen_string_literal: true

class AddPendingStartedAtIndexToContracts < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  # The activation clock reads pending contracts whose start has arrived.
  def change
    add_index :contracts, :started_at,
      where: "status = 'pending'",
      algorithm: :concurrently,
      if_not_exists: true,
      name: "index_contracts_on_started_at_pending"
  end
end
