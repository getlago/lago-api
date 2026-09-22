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

  let(:bucket_wait) { Yabeda.realtime_usage.wallet_refresh_bucket_wait }
  let(:unknown_codes) { Yabeda.realtime_usage.wallet_refresh_unknown_codes_total }

  before do
    allow(Customers::RefreshWalletsService).to receive(:call).and_return(refresh_result)
    allow(bucket_wait).to receive(:measure)
    allow(unknown_codes).to receive(:increment)
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

    context "with unknown targeted wallet codes" do
      let(:wallet_codes) { ["nope"] }

      it "still refreshes (the cascade covers every wallet)" do
        expect(service_result).to be_success
        expect(Customers::RefreshWalletsService).to have_received(:call).with(customer:)
      end

      it "counts the codes the customer does not hold" do
        service_result

        expect(unknown_codes).to have_received(:increment)
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
      stub_const("#{described_class}::BUCKET_WAIT_TIMEOUT", 0.2)
      allow(Rails.logger).to receive(:warn)
    end

    context "when the bucket has caught up to the watermark" do
      before do
        create(:clickhouse_usage_bucket, organization:, customer:, subscription:, last_ingested_at: watermark + 1.second)
      end

      it "refreshes without warning" do
        expect(service_result).to be_success
        expect(Customers::RefreshWalletsService).to have_received(:call).with(customer:)
        expect(Rails.logger).not_to have_received(:warn).with(/usage buckets did not catch up/)
      end

      it "measures the wait" do
        service_result

        expect(bucket_wait).to have_received(:measure).with({}, be_within(60).of(0))
      end
    end

    context "when only another organization holds a bucket for that subscription id" do
      let(:other_organization) { create(:organization) }

      before do
        create(
          :clickhouse_usage_bucket,
          organization:, customer:, subscription:,
          organization_id: other_organization.id,
          last_ingested_at: watermark + 1.second
        )
      end

      it "does not treat it as caught up" do
        expect(service_result).to be_success
        expect(Rails.logger).to have_received(:warn).with(/usage buckets did not catch up/)
      end

      it "leaves the refresh to the sweep" do
        expect(service_result).to be_success
        expect(Customers::RefreshWalletsService).not_to have_received(:call)
      end
    end

    context "when the buckets never catch up" do
      it "does not refresh, so the customer stays flagged for the sweep" do
        expect(service_result).to be_success
        expect(Customers::RefreshWalletsService).not_to have_received(:call)
        expect(Rails.logger).to have_received(:warn).with(/usage buckets did not catch up/)
      end

      it "reports the reason it walked away" do
        expect(service_result.reason).to eq(:bucket_wait_timeout)
      end

      it "measures the wait it gave up on" do
        service_result

        expect(bucket_wait).to have_received(:measure)
      end
    end

    context "when the watermark is older than the stale cutoff" do
      let(:watermark) { 1.minute.ago }

      context "when the bucket landed" do
        before do
          create(:clickhouse_usage_bucket, organization:, customer:, subscription:, last_ingested_at: watermark + 1.second)
        end

        it "refreshes without waiting for the buckets" do
          expect(service_result).to be_success
          expect(Customers::RefreshWalletsService).to have_received(:call).with(customer:)
          expect(Rails.logger).not_to have_received(:warn).with(/usage buckets/)
        end
      end

      context "without a bucket at the watermark" do
        it "leaves the refresh to the sweep rather than waiting it out" do
          expect(service_result).to be_success
          expect(Customers::RefreshWalletsService).not_to have_received(:call)
          expect(Rails.logger).to have_received(:warn).with(/behind a stale watermark/)
        end

        it "reports the reason it walked away" do
          expect(service_result.reason).to eq(:stale_watermark)
        end
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
