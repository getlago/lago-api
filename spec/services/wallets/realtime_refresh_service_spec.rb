# frozen_string_literal: true

require "rails_helper"

RSpec.describe Wallets::RealtimeRefreshService, clickhouse: {clean_before: true}, transaction: false do
  subject(:service_result) do
    described_class.call(organization_id: organization.id, customer_id: customer.id, wallet_codes:)
  end

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:wallet_codes) { [] }

  let(:refresh_result) do
    Customers::RefreshWalletsService::Result.new.tap { |r| r.wallets = [] }
  end

  let(:duration) { Yabeda.realtime_usage.wallet_refresh_duration }

  before do
    allow(Customers::RefreshWalletsService).to receive(:call).and_return(refresh_result)
    allow(duration).to receive(:measure)
  end

  context "with an active wallet" do
    before { create(:wallet, customer:, organization:) }

    it "refreshes the customer wallets" do
      expect(service_result).to be_success
      expect(Customers::RefreshWalletsService).to have_received(:call).with(customer:)
    end

    it "reports no reason, since it did refresh" do
      expect(service_result.reason).to be_nil
    end

    it "measures how long the refresh took" do
      service_result

      expect(duration).to have_received(:measure).with({}, be_within(60).of(0))
    end

    context "with unknown targeted wallet codes" do
      let(:wallet_codes) { ["nope"] }

      it "still refreshes (the cascade covers every wallet)" do
        expect(service_result).to be_success
        expect(Customers::RefreshWalletsService).to have_received(:call).with(customer:)
      end
    end
  end

  context "without an active wallet" do
    it "does nothing" do
      expect(service_result).to be_success
      expect(Customers::RefreshWalletsService).not_to have_received(:call)
    end
  end

  describe "the bucket wait" do
    subject(:service_result) do
      described_class.call(
        organization_id: organization.id,
        customer_id: customer.id,
        expected_ingested_at: {subscription.id => watermark_ms}
      )
    end

    let(:plan) { create(:plan, organization:) }
    let(:subscription) { create(:subscription, organization:, customer:, plan:) }
    let(:watermark) { Time.current }
    let(:watermark_ms) { (watermark.to_f * 1000).to_i }

    before do
      create(:wallet, customer:, organization:)
      stub_const("RealtimeUsage::BucketWatermark::TIMEOUT", 0.2)
    end

    context "when the bucket has caught up to the watermark" do
      before do
        create(:clickhouse_usage_bucket, organization:, customer:, subscription:, last_ingested_at: watermark + 1.second)
      end

      it "refreshes" do
        expect(service_result).to be_success
        expect(Customers::RefreshWalletsService).to have_received(:call).with(customer:)
      end

      it "reads the usage with sequential consistency" do
        consistency = nil
        allow(Customers::RefreshWalletsService).to receive(:call) do
          consistency = Clickhouse::BaseRecord.connection.select_value("SELECT getSetting('select_sequential_consistency')").to_i
          refresh_result
        end

        service_result

        expect(consistency).to eq(1)
      end
    end

    context "when the buckets never catch up" do
      it "does not refresh, so the customer stays flagged for the sweep" do
        expect(service_result).to be_success
        expect(Customers::RefreshWalletsService).not_to have_received(:call)
      end

      it "reports the reason it walked away" do
        expect(service_result.reason).to eq(:bucket_wait_timeout)
      end
    end

    context "when the watermark is older than the stale cutoff" do
      let(:watermark) { 1.minute.ago }

      it "leaves the refresh to the sweep and reports why" do
        expect(service_result.reason).to eq(:stale_watermark)
        expect(Customers::RefreshWalletsService).not_to have_received(:call)
      end
    end
  end

  context "with an unknown customer" do
    subject(:service_result) do
      described_class.call(organization_id: organization.id, customer_id: SecureRandom.uuid)
    end

    it "does nothing" do
      expect(service_result).to be_success
      expect(Customers::RefreshWalletsService).not_to have_received(:call)
    end
  end
end
