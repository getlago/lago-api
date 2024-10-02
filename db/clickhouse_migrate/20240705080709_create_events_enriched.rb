# frozen_string_literal: true

class CreateEventsEnriched < ActiveRecord::Migration[7.1]
  def change
    options = <<-SQL
    ReplacingMergeTree(timestamp)
    PRIMARY KEY (
      organization_id,
      code,
      external_subscription_id,
      toDate(timestamp)
    )
    ORDER BY (
      organization_id,
      code
      external_subscription_id,
      toDate(timestamp),
      transaction_id,
      timestamp
    )
    SQL

    create_table :events_enriched, id: false, options: do |t|
      t.string :organization_id, null: false
      t.string :external_subscription_id, null: false
      t.string :code, null: false
      t.datetime :timestamp, null: false, precision: 3
      t.string :transaction_id, null: false
      t.string :properties, map: true, null: false
      t.string :ingested_at, null: false
      t.string :value
      t.decimal :numeric_value, precision: 26
    end
  end
end
