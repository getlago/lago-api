# frozen_string_literal: true

require "rails_helper"

RSpec.describe "ClickHouse transaction_id indexes", clickhouse: true do # rubocop:disable RSpec/DescribeClass
  subject(:indexes) do
    Clickhouse::BaseRecord.connection.select_values(<<~SQL)
      SELECT concat(table, '.', name)
      FROM system.data_skipping_indices
      WHERE database = currentDatabase()
        AND type = 'bloom_filter'
        AND expr = 'transaction_id'
        AND granularity = 1
    SQL
  end

  it "defines a Bloom-filter index on transaction_id for raw and enriched events" do
    expect(indexes).to match_array(
      %w[
        events_raw.idx_events_raw_transaction_id
        events_enriched.idx_events_enriched_transaction_id
      ]
    )
  end
end
