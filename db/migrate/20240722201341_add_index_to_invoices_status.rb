# frozen_string_literal: true

class AddIndexToInvoicesStatus < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_index :invoices, :status,
      algorithm: :concurrently,
      if_not_exists: true
  end
end
