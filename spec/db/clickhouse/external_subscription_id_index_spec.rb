# frozen_string_literal: true

require "rails_helper"

RSpec.describe "ClickHouse external_subscription_id index", clickhouse: true do # rubocop:disable RSpec/DescribeClass
  subject(:indexes) do
    Clickhouse::BaseRecord.connection.select_values(<<~SQL)
      SELECT concat(table, '.', name)
      FROM system.data_skipping_indices
      WHERE database = currentDatabase()
        AND table = 'events_enriched'
        AND type = 'bloom_filter'
        AND expr = 'external_subscription_id'
        AND granularity = 1
    SQL
  end

  it "defines an external_subscription_id Bloom-filter index on enriched events" do
    expect(indexes).to eq(%w[events_enriched.idx_external_subscription_id])
  end
end
