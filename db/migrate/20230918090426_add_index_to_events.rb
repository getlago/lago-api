# frozen_string_literal: true

class AddIndexToEvents < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def change
    add_index :events, %w[subscription_id code timestamp], where: "deleted_at IS NULL", algorithm: :concurrently
    remove_index :events, %w[subscription_id code]
  end
end
