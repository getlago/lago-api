# frozen_string_literal: true

RSpec.shared_context "with realtime usage availability" do
  include_context "with clickhouse availability"

  let(:realtime_usage_enabled) { "true" }
  let(:premium_license) { true }

  before do
    ENV["LAGO_REALTIME_USAGE_ENABLED"] = realtime_usage_enabled
    allow(License).to receive(:premium?).and_return(premium_license)
  end

  after { ENV["LAGO_REALTIME_USAGE_ENABLED"] = nil }
end
