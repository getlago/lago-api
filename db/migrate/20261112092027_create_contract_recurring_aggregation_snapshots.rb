# frozen_string_literal: true

class CreateContractRecurringAggregationSnapshots < ActiveRecord::Migration[8.1]
  def change
    create_table :contract_recurring_aggregation_snapshots, id: :uuid do |t|
      t.references :organization, type: :uuid, null: false, foreign_key: true, index: false
      t.references :contract, type: :uuid, null: false, foreign_key: true, index: false
      t.references :product, type: :uuid, null: false, foreign_key: true, index: false
      t.references :product_filter, type: :uuid, foreign_key: true, index: false
      t.references :billable_metric, type: :uuid, null: false, foreign_key: true, index: false

      t.jsonb :grouped_by, null: false, default: {}
      t.datetime :to_datetime, null: false
      t.datetime :watermark, null: false
      t.decimal :units, null: false, default: 0
      t.bigint :events_count, null: false, default: 0
      t.jsonb :presentation_breakdowns, null: false, default: []
      # Filter precedence depends on which filters the segment prices, which no row edit reveals.
      t.uuid :priced_product_filter_ids, array: true, null: false, default: []

      t.timestamps

      # Both lookups lead on contract_id, so it gets no index of its own. grouped_by sits before
      # to_datetime in the unique index, so the latest period lookup needs the second one.
      t.index %i[contract_id product_id product_filter_id grouped_by to_datetime],
        unique: true, nulls_not_distinct: true, name: "idx_contract_recurring_snapshots_unique"
      t.index %i[contract_id product_id product_filter_id to_datetime], name: "idx_contract_recurring_snapshots_by_period"
      t.index :organization_id, name: "idx_contract_recurring_snapshots_on_organization_id"
      t.index :product_id, name: "idx_contract_recurring_snapshots_on_product_id"
      t.index :product_filter_id, name: "idx_contract_recurring_snapshots_on_product_filter_id"
      t.index :billable_metric_id, name: "idx_contract_recurring_snapshots_on_billable_metric_id"
    end
  end
end
