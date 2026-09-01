# frozen_string_literal: true

RSpec.shared_context "with realtime usage availability" do
  include_context "with clickhouse availability"

  let(:risingwave_usage_enabled) { "true" }

  before { ENV["LAGO_RISINGWAVE_USAGE_ENABLED"] = risingwave_usage_enabled }
  after { ENV["LAGO_RISINGWAVE_USAGE_ENABLED"] = nil }
end
