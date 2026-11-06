# frozen_string_literal: true

class AddFeesProductCursorIndex < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    if index_exists?(:fees, nil, name: :index_fees_by_product_cursor, valid: false)
      remove_index :fees, name: :index_fees_by_product_cursor, algorithm: :concurrently
    end

    # 6 is `Fee::FEE_TYPES` `product`: legacy fees are left out, so a v2 page never walks past them.
    add_index :fees,
      [:organization_id, :created_at, :id],
      order: {created_at: :desc, id: :desc},
      where: "deleted_at IS NULL AND fee_type = 6",
      name: :index_fees_by_product_cursor,
      algorithm: :concurrently,
      if_not_exists: true
  end

  def down
    remove_index :fees, name: :index_fees_by_product_cursor, algorithm: :concurrently, if_exists: true
  end
end
