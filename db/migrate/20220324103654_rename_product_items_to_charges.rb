# frozen_string_literal: true

class RenameProductItemsToCharges < ActiveRecord::Migration[7.0]
  def change
    rename_table :product_items, :charges
    remove_column :charges, :product_id

    change_table :charges do |t|
      t.references :plan, type: :uuid, foreign_key: true, index: true
    end
  end
end