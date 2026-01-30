# frozen_string_literal: true

RSpec.describe Utils::SecurityLog do
  subject(:security_log) { described_class }

  describe ".available?" do
    subject { security_log.available? }

    include_context "with security log infrastructure"

    context "when infrastructure is configured" do
      it { is_expected.to be_truthy }
    end

    context "when clickhouse is not configured" do
      let(:clickhouse_enabled) { nil }

      it { is_expected.to be_falsey }
    end

    context "when kafka bootstrap servers are not configured" do
      let(:kafka_bootstrap_servers) { nil }

      it { is_expected.to be_falsey }
    end

    context "when kafka topic is not configured" do
      let(:kafka_security_logs_topic) { nil }

      it { is_expected.to be_falsey }
    end
  end

  describe ".produce" do
    subject do
      security_log.produce(
        organization: organization,
        log_type: "user",
        log_event: "user.signed_up"
      )
    end

    let(:organization) { create(:organization) }

    include_context "with security log infrastructure"

    context "when infrastructure is configured" do
      it { is_expected.to be true }
    end

    context "when infrastructure is not configured" do
      let(:clickhouse_enabled) { nil }

      it { is_expected.to be false }
    end
  end
end
