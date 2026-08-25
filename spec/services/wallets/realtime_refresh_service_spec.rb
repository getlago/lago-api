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

  before do
    allow(Customers::RefreshWalletsService).to receive(:call).and_return(refresh_result)
  end

  context "with an active wallet" do
    before { create(:wallet, customer:, organization:) }

    it "refreshes the customer wallets" do
      expect(service_result).to be_success
      expect(Customers::RefreshWalletsService).to have_received(:call).with(customer:)
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
        expected_ingested_at: {subscription.id => watermark.to_i}
      )
    end

    let(:subscription) { create(:subscription, customer:, plan: create(:plan, organization:)) }
    let(:watermark) { Time.zone.parse("2026-08-24 10:00:00").to_f * 1000 }

    def insert_bucket(organization_id:, subscription_id:, ingested_at:)
      Clickhouse::UsageBucket.insert_all([
        {
          bucket: Time.zone.parse("2026-08-24 10:00:00"),
          organization_id:,
          subscription_id:,
          customer_id: customer.id,
          code: "bm",
          charge_id: SecureRandom.uuid,
          charge_filter_id: "",
          grouped_by: "{}",
          aggregation_type: "sum",
          events_count: 1,
          units: 1,
          last_event_at: Time.zone.parse("2026-08-24 10:00:00"),
          last_ingested_at: ingested_at
        }
      ])
    end

    before do
      create(:wallet, customer:, organization:)
      stub_const("#{described_class}::BUCKET_WAIT_TIMEOUT", 0.2)
    end

    context "when the bucket has caught up to the watermark" do
      before { insert_bucket(organization_id: organization.id, subscription_id: subscription.id, ingested_at: Time.zone.parse("2026-08-24 10:00:01")) }

      it "refreshes without warning" do
        allow(Rails.logger).to receive(:warn)
        expect(service_result).to be_success
        expect(Customers::RefreshWalletsService).to have_received(:call).with(customer:)
        expect(Rails.logger).not_to have_received(:warn).with(/usage buckets did not catch up/)
      end
    end

    context "when only another organization holds a bucket for that subscription id" do
      before { insert_bucket(organization_id: create(:organization).id, subscription_id: subscription.id, ingested_at: Time.zone.parse("2026-08-24 10:00:01")) }

      it "does not treat it as caught up" do
        allow(Rails.logger).to receive(:warn)
        expect(service_result).to be_success
        expect(Rails.logger).to have_received(:warn).with(/usage buckets did not catch up/)
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
