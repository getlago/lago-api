# frozen_string_literal: true

RSpec.shared_context "with security log infrastructure" do
  include_context "with Kafka log infrastructure"

  let(:kafka_security_logs_topic) { "security_logs" }

  before { ENV["LAGO_KAFKA_SECURITY_LOGS_TOPIC"] = kafka_security_logs_topic }
  after { ENV["LAGO_KAFKA_SECURITY_LOGS_TOPIC"] = nil }
end
