# frozen_string_literal: true

# The v2 contracts list always filters on one status (`active` by default), which the
# `(organization_id, created_at DESC, id DESC)` cursor index cannot use: each page would walk
# the contracts of every status in order and discard the others. With `status` second, a
# single-status page is an ordered index scan. `index_contracts_by_cursor` stays for the
# requests asking for several statuses, which this one cannot serve in order.
class AddContractsStatusCursorIndex < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    # A failed concurrent build leaves an invalid index behind, which `if_not_exists`
    # would then keep: drop it so that a retry builds the index again.
    if index_exists?(:contracts, nil, name: :index_contracts_by_status_cursor, valid: false)
      remove_index :contracts, name: :index_contracts_by_status_cursor, algorithm: :concurrently
    end

    # strong_migrations doubts non-unique indexes past three columns. A keyset index needs
    # all four: two equality filters, then the tuple that both bounds and orders the page.
    safety_assured do
      add_index :contracts,
        [:organization_id, :status, :created_at, :id],
        order: {created_at: :desc, id: :desc},
        name: :index_contracts_by_status_cursor,
        algorithm: :concurrently,
        if_not_exists: true
    end
  end

  def down
    remove_index :contracts, name: :index_contracts_by_status_cursor, algorithm: :concurrently, if_exists: true
  end
end
