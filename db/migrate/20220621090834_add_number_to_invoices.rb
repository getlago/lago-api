# frozen_string_literal: true

class AddNumberToInvoices < ActiveRecord::Migration[7.0]
  def change
    # NOTE: sequential_id scope change we have to reset the column
    safety_assured do
      change_table :invoices, bulk: true do |t|
        t.remove_index :sequential_id
        t.remove :sequential_id, type: :integer

        t.string :number, null: false, index: true, default: ''
        t.integer :sequential_id, index: true
      end
    end
  end
end
