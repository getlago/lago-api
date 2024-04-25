# frozen_string_literal: true

class CreateIntegrationCustomers < ActiveRecord::Migration[7.0]
  def change
    create_table :integration_customers, id: :uuid do |t|
      t.references :integration, null: false, foreign_key: true, type: :uuid
      t.references :customer, null: false, foreign_key: true, type: :uuid
      t.string :external_customer_id, null: false
      t.string :type, null: false
      t.jsonb 'settings', default: {}, null: false

      t.index %i[customer_id type], unique: true
      t.index :external_customer_id

      t.timestamps
    end
  end
end
