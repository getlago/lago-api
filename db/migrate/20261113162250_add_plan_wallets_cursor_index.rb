# frozen_string_literal: true

class AddPlanWalletsCursorIndex < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    # A failed concurrent build leaves an invalid index behind, which `if_not_exists`
    # would then keep: drop it so that a retry builds the index again.
    if index_exists?(:plan_wallets, nil, name: :index_plan_wallets_by_cursor, valid: false)
      remove_index :plan_wallets, name: :index_plan_wallets_by_cursor, algorithm: :concurrently
    end

    add_index :plan_wallets,
      [:catalog_plan_id, :created_at, :id],
      order: {created_at: :desc, id: :desc},
      where: "deleted_at IS NULL",
      name: :index_plan_wallets_by_cursor,
      algorithm: :concurrently,
      if_not_exists: true
  end

  def down
    remove_index :plan_wallets, name: :index_plan_wallets_by_cursor, algorithm: :concurrently, if_exists: true
  end
end
