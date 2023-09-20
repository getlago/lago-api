# frozen_string_literal: true

class AddIndexToEvents < ActiveRecord::Migration[7.0]
  def change
    disable_ddl_transaction!

    add_index :events, %w[subscription_id code timestamp], where: 'deleted_at IS NULL', algorithm: :concurrently
    remove_index :events, %w[subscription_id code]
  end
end
