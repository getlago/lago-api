# frozen_string_literal: true

require "rails_helper"

RSpec.describe "ClickHouse enriched_at index", clickhouse: true do # rubocop:disable RSpec/DescribeClass
  subject(:indexes) do
    Clickhouse::BaseRecord.connection.select_values(<<~SQL)
      SELECT concat(table, '.', name)
      FROM system.data_skipping_indices
      WHERE database = currentDatabase()
        AND type = 'minmax'
        AND expr = 'enriched_at'
        AND granularity = 1
    SQL
  end

  it "defines a minmax index on enriched_at for enriched events" do
    expect(indexes).to eq(%w[events_enriched.idx_enriched_at])
  end
end
