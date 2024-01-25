# frozen_string_literal: true

class AddGroupedByToAdjustedFees < ActiveRecord::Migration[7.0]
  def change
    add_column :adjusted_fees, :grouped_by, :jsonb, null: false, default: {}
  end
end
