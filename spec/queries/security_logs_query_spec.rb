# frozen_string_literal: true

require "rails_helper"

RSpec.describe SecurityLogsQuery do
  subject(:result) { described_class.call(organization:, pagination:, filters:) }

  let(:organization) { create(:organization, premium_integrations: ["security_logs"]) }
  let(:pagination) { {page: 1, limit: 10} }
  let(:filters) { {to_date: Time.current} }

  before { allow(License).to receive(:premium?).and_return(true) }

  describe ".available?" do
    subject { described_class.available? }

    include_context "with clickhouse availability"

    context "when clickhouse is available" do
      it { is_expected.to be true }
    end

    context "when clickhouse is not available" do
      let(:clickhouse_enabled) { nil }

      it { is_expected.to be false }
    end
  end

  describe "#call" do
    include_context "with clickhouse availability"

    context "when all conditions are met" do
      it "returns empty collection (stub)" do
        expect(result).to be_success
        expect(result.security_logs).to eq([])
      end
    end

    context "when clickhouse is not available" do
      let(:clickhouse_enabled) { nil }

      it "returns forbidden failure" do
        expect(result).to be_failure
        expect(result.error).to be_a(BaseService::ForbiddenFailure)
      end
    end

    context "when security_logs is not enabled" do
      let(:organization) { create(:organization, premium_integrations: []) }

      it "returns forbidden failure" do
        expect(result).to be_failure
        expect(result.error).to be_a(BaseService::ForbiddenFailure)
      end
    end
  end
end
