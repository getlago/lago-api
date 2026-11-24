# frozen_string_literal: true

require "rails_helper"

RSpec.describe RealtimeUsage::BucketWatermark, clickhouse: {clean_before: true}, transaction: false do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, organization:, customer:) }
  let(:bucket_wait) { Yabeda.realtime_usage.bucket_wait }

  def sequential_consistency
    Clickhouse::BaseRecord.connection.select_value("SELECT getSetting('select_sequential_consistency')").to_i
  end

  describe ".wait" do
    subject(:reason) do
      described_class.wait(organization_id: organization.id, pending: {subscription.id => watermark_ms}, lane: :wallet_refresh)
    end

    let(:watermark) { Time.current }
    let(:watermark_ms) { (watermark.to_f * 1000).to_i }

    before do
      stub_const("#{described_class}::TIMEOUT", 0.2)
      allow(bucket_wait).to receive(:measure)
      allow(Rails.logger).to receive(:warn)
    end

    context "when the bucket has caught up to the watermark" do
      before do
        create(:clickhouse_usage_bucket, organization:, customer:, subscription:, last_ingested_at: watermark + 1.second)
      end

      it "returns no reason, without warning" do
        expect(reason).to be_nil
        expect(Rails.logger).not_to have_received(:warn)
      end

      it "measures the wait under its lane" do
        reason

        expect(bucket_wait).to have_received(:measure).with({lane: :wallet_refresh}, be_within(60).of(0))
      end

      it "polls with sequential consistency" do
        consistency = nil
        allow(Clickhouse::UsageBucket).to receive(:uncached).and_wrap_original do |original, &block|
          consistency = sequential_consistency
          original.call(&block)
        end

        reason

        expect(consistency).to eq(1)
      end
    end

    context "when only another organization holds a bucket for that subscription id" do
      before do
        create(
          :clickhouse_usage_bucket,
          organization:, customer:, subscription:,
          organization_id: create(:organization).id,
          last_ingested_at: watermark + 1.second
        )
      end

      it "does not treat it as caught up" do
        expect(reason).to eq(:bucket_wait_timeout)
      end
    end

    context "when the buckets never catch up" do
      it "gives up with the reason and a warning" do
        expect(reason).to eq(:bucket_wait_timeout)
        expect(Rails.logger).to have_received(:warn).with(/usage buckets did not catch up lane=wallet_refresh/)
      end

      it "measures the wait it gave up on" do
        reason

        expect(bucket_wait).to have_received(:measure).with({lane: :wallet_refresh}, be_within(60).of(0))
      end
    end

    context "when the watermark is older than the stale cutoff" do
      let(:watermark) { 1.minute.ago }

      context "when the bucket landed" do
        before do
          create(:clickhouse_usage_bucket, organization:, customer:, subscription:, last_ingested_at: watermark + 1.second)
        end

        it "returns no reason" do
          expect(reason).to be_nil
          expect(Rails.logger).not_to have_received(:warn)
        end
      end

      context "without a bucket at the watermark" do
        it "gives up without waiting it out" do
          expect(reason).to eq(:stale_watermark)
          expect(Rails.logger).to have_received(:warn).with(/behind a stale watermark/)
        end
      end
    end

    context "without a pending subscription" do
      subject(:reason) { described_class.wait(organization_id: organization.id, pending: {}, lane: :wallet_refresh) }

      it "returns no reason without measuring a wait" do
        expect(reason).to be_nil
        expect(bucket_wait).not_to have_received(:measure)
      end
    end
  end

  describe ".consistent_reads" do
    it "reads with sequential consistency inside the block only" do
      inside = described_class.consistent_reads { sequential_consistency }

      expect(inside).to eq(1)
      expect(sequential_consistency).to eq(0)
    end
  end
end
