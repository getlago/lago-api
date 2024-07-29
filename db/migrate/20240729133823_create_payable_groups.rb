# frozen_string_literal: true

class CreatePayableGroups < ActiveRecord::Migration[7.1]
  def change
    create_table :payable_groups, id: :uuid do |t|
      t.references :customer, null: false, foreign_key: true, type: :uuid
      t.integer :payment_status, null: false, default: 0
      t.timestamps
    end

    add_column :invoices, :payable_group_id, :uuid
  end
end
