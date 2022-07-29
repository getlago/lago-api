class AddPropertiesToFees < ActiveRecord::Migration[7.0]
  def change
    add_column :fees, :properties, :jsonb, null: false, default: {}
  end
end
