# frozen_string_literal: true

RSpec.shared_context "with API log infrastructure" do
  include_context "with Kafka log infrastructure"

  let(:kafka_api_logs_topic) { "api_logs" }
  let(:api_log_payload) { JSON.parse(kafka_messages.find { it[:topic] == kafka_api_logs_topic }[:payload]) }

  before { ENV["LAGO_KAFKA_API_LOGS_TOPIC"] = kafka_api_logs_topic }
  after { ENV["LAGO_KAFKA_API_LOGS_TOPIC"] = nil }
end
