# frozen_string_literal: true

class AddExecutionRecordToOrders < ActiveRecord::Migration[8.0]
  def change
    add_column :orders, :execution_record, :jsonb, default: {}, null: false
  end
end
