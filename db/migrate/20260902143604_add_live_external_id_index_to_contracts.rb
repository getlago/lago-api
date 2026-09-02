# frozen_string_literal: true

class AddLiveExternalIdIndexToContracts < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    # One live agreement per external id, per status: the create service's
    # check is only advisory under concurrency, this closes the race. Unique
    # per status on purpose — replacement flows need one pending and one
    # active to coexist, never two of either.
    add_index :contracts, %i[organization_id external_id status],
      unique: true,
      where: "status IN ('pending', 'active')",
      name: "index_contracts_on_live_external_id",
      algorithm: :concurrently
  end
end
