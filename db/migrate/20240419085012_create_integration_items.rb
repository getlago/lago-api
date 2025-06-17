# frozen_string_literal: true

class CreateIntegrationItems < ActiveRecord::Migration[7.0]
  def change
    create_table :integration_items, id: :uuid do |t|
      t.references :integration, type: :uuid, foreign_key: true, null: false, index: true
      t.integer :item_type, null: false
      t.string :external_id, null: false
      t.string :account_code
      t.string :name

      t.timestamps
    end
  end
end
