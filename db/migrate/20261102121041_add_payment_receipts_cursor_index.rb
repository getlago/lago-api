# frozen_string_literal: true

class AddPaymentReceiptsCursorIndex < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    # A failed concurrent build leaves an invalid index that must be rebuilt on retry.
    if index_exists?(:payment_receipts, nil, name: :index_payment_receipts_by_cursor, valid: false)
      remove_index :payment_receipts, name: :index_payment_receipts_by_cursor, algorithm: :concurrently
    end

    add_index :payment_receipts,
      [:organization_id, :created_at, :id],
      order: {created_at: :desc, id: :desc},
      name: :index_payment_receipts_by_cursor,
      algorithm: :concurrently,
      if_not_exists: true
  end

  def down
    remove_index :payment_receipts, name: :index_payment_receipts_by_cursor, algorithm: :concurrently, if_exists: true
  end
end
