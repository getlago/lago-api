# frozen_string_literal: true

class AddSourceToEvents < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_column :events, :source, :integer, default: 0, null: false
    add_index :events, :source, algorithm: :concurrently
  end
end
