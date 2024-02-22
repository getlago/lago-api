class CreateTimebasedEvents < ActiveRecord::Migration[7.0]
  def change
    create_table :timebased_events, id: :uuid do |t|
      t.references :organization, null: false, foreign_key: true, type: :uuid
      t.references :invoice, null: true, foreign_key: true, type: :uuid
      t.integer :event_type
      t.datetime :timestamp
      t.string :external_customer_id
      t.string :external_subscription_id
      t.jsonb :metadata

      t.timestamps
    end
  end
end
