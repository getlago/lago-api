# frozen_string_literal: true

class AddDeletedAtToFees < ActiveRecord::Migration[7.1]
  def change
    add_column :fees, :deleted_at, :datetime
    add_index :fees, :deleted_at
  end
end
