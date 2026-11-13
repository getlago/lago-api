# frozen_string_literal: true

# ClickHouse and Kafka settings shared by the log contexts. Each one adds its own topic.
RSpec.shared_context "with Kafka log infrastructure" do
  let(:clickhouse_enabled) { "true" }
  let(:kafka_bootstrap_servers) { "kafka" }

  before do
    ENV["LAGO_CLICKHOUSE_ENABLED"] = clickhouse_enabled
    ENV["LAGO_KAFKA_BOOTSTRAP_SERVERS"] = kafka_bootstrap_servers
  end

  after do
    ENV["LAGO_CLICKHOUSE_ENABLED"] = nil
    ENV["LAGO_KAFKA_BOOTSTRAP_SERVERS"] = nil
  end
end
