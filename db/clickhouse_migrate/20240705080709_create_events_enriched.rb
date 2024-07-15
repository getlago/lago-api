# frozen_string_literal: true

class CreateEventsEnriched < ActiveRecord::Migration[7.1]
  def change
    options = <<-SQL
    ReplacingMergeTree
    ORDER BY (
      organization_id,
      external_subscription_id,
      code,
      charge_id,
      transaction_id
    )
    SQL

    create_table :events_enriched, id: false, options: do |t|
      t.string :organization_id, null: false
      t.string :external_subscription_id, null: false
      t.string :code, null: false
      t.datetime :timestamp, null: false, precision: 3
      t.string :transaction_id, null: false
      t.map :properties, key_type: :string, value_type: :string, null: false
      t.string :value
      t.string :charge_id, null: false
      t.string :aggregation_type
      t.map :filters, key_type: :string, value_type: 'Array(String)', null: false
      t.map :grouped_by, key_type: :string, value_type: :string, null: false
    end
  end
end
