# frozen_string_literal: true

class CreateCustomerMetadata < ActiveRecord::Migration[7.0]
  def change
    create_table :customer_metadata, id: :uuid do |t|
      t.references :customer, type: :uuid, null: false, foreign_key: true, index: true

      t.string :key, null: false
      t.string :value, null: false
      t.boolean :display_in_invoice, default: false, null: false

      t.timestamps
    end
  end
end
