# frozen_string_literal: true

class AddIndexOnPayableGroupId < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_index :invoices, :payable_group_id, algorithm: :concurrently, if_not_exists: true
  end
end
