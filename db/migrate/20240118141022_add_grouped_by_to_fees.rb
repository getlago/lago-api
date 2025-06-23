# frozen_string_literal: true

class AddGroupedByToFees < ActiveRecord::Migration[7.0]
  def change
    add_column :fees, :grouped_by, :string, array: true, null: false, default: []
  end
end
