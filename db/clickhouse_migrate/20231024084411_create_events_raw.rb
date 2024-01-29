class CreateEventsRaw < ActiveRecord::Migration[7.0]
  def change
    options = <<-SQL
      MergeTree
      PRIMARY KEY (organization_id, external_subscription_id, code, toStartOfDay(timestamp))
      TTL
        toDateTime(timestamp) TO VOLUME 'hot',
        toDateTime(timestamp) + INTERVAL 90 DAY TO VOLUME 'cold'
      SETTINGS
        storage_policy = 'hot_cold';
    SQL

    create_table :events_raw, id: false, options: do |t|
      t.string :organization_id, null: false
      t.string :external_customer_id, null: false
      t.string :external_subscription_id, null: false
      t.string :transaction_id, null: false
      t.datetime :timestamp, null: false, precision: 3
      t.string :code, null: false
      t.map :properties, key_type: :string, value_type: :string, null: false
    end
  end
end
