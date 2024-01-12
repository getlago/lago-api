# frozen_string_literal: true

class AddChargeFilterIdToFees < ActiveRecord::Migration[7.0]
  def change
    add_column :fees, :charge_filter_id, :uuid, null: true
    add_index :fees, :charge_filter_id
  end
end
