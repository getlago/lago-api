# frozen_string_literal: true

class CreateCustomerMetadata < ActiveRecord::Migration[7.0]
  def change
    create_table :customer_metadata, id: :uuid do |t|
      t.references :customer, type: :uuid, null: false, foreign_key: true, index: true

      t.string :key, null: false
      t.string :value, null: false
      t.boolean :display_in_invoice, default: false, null: false

      t.timestamps

      t.index %w[customer_id key], name: "index_customer_metadata_on_customer_id_and_key", unique: true
    end
  end
end
