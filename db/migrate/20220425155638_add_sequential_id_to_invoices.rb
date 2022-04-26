# frozen_string_literal: true

class AddSequentialIdToInvoices < ActiveRecord::Migration[7.0]
  def change
    add_column :invoices, :sequential_id, :integer
    add_index :invoices, :sequential_id
  end
end
