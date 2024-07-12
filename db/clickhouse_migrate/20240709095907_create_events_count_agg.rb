# frozen_string_literal: false

class CreateEventsCountAgg < ActiveRecord::Migration[7.1]
  def change
    options = <<-SQL
      SummingMergeTree
      PRIMARY KEY (organization_id, external_subscription_id, code, charge_id, timestamp, filters, grouped_by)
    SQL

    create_table :events_count_agg, id: false, options: do |t|
      t.string :organization_id, null: false
      t.string :external_subscription_id, null: false
      t.string :code, null: false
      t.string :charge_id, null: false
      t.decimal :value, precision: 26
      t.datetime :timestamp, precision: 3, null: false
      t.map :filters, key_type: :string, value_type: 'Array(String)', null: false
      t.map :grouped_by, key_type: :string, value_type: :string, null: false
    end
  end
end
