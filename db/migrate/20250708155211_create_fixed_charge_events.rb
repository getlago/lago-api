class CreateFixedChargeEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :fixed_charge_events, id: :uuid do |t|
      t.references :organization, null: false, foreign_key: true, type: :uuid
      t.references :customer, null: false, foreign_key: true, type: :uuid
      t.string :code, null: false
      t.jsonb :properties, default: {}, null: false
      t.timestamp :timestamp, null: false
      t.references :subscription, null: false, foreign_key: true, type: :uuid
      t.timestamp :deleted_at

      t.timestamps
    end

    add_index :fixed_charge_events, :code
    # do we need to index code scoped to organization_id, subscription_id or customer_id
  end
end
