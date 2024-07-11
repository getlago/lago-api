# frozen_string_literal: true

class AddFeeDeletedAtIndex < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_index :fees, :deleted_at, algorithm: :concurrently, if_not_exists: true
  end
end
