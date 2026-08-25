# frozen_string_literal: true

require "rails_helper"

RSpec.describe Clickhouse::BaseRecord, clickhouse: true do
  describe ".connection" do
    it "defines Bloom-filter indexes for raw and enriched event transaction IDs" do
      indexes = described_class.connection.select_values(<<~SQL)
        SELECT concat(table, '.', name)
        FROM system.data_skipping_indices
        WHERE database = currentDatabase()
          AND table IN ('events_raw', 'events_enriched')
          AND name IN ('idx_events_raw_transaction_id', 'idx_events_enriched_transaction_id')
          AND type = 'bloom_filter'
          AND expr = 'transaction_id'
          AND granularity = 1
      SQL

      expect(indexes).to match_array(
        %w[
          events_raw.idx_events_raw_transaction_id
          events_enriched.idx_events_enriched_transaction_id
        ]
      )
    end
  end
end
