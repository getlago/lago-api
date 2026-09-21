# frozen_string_literal: true

require "rails_helper"

RSpec.describe WalletRefreshTriggersConsumer do
  subject(:consumer) { karafka.consumer_for(ENV["LAGO_KAFKA_REALTIME_USAGE_TRIGGERS_TOPIC"]) }

  include_context "with realtime usage availability"

  let(:organization) do
    create(:organization, clickhouse_events_store: true, feature_flags: ["realtime_usage"])
  end
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:subscription) { create(:subscription, organization:, customer:, plan:) }
  let(:watermark_ms) { (Time.current.to_f * 1000).to_i }

  let(:refresh_result) do
    Wallets::RealtimeRefreshService::Result.new.tap { |r| r.wallets = [] }
  end

  let(:trigger) do
    {
      organization_id: organization.id,
      customer_id: customer.id,
      subscription_id: subscription.id,
      last_ingested_at: watermark_ms,
      target_wallet_code: nil
    }
  end

  let(:wallet_status) { :active }

  before do
    create(:wallet, customer:, organization:, status: wallet_status)
    allow(Wallets::RealtimeRefreshService).to receive(:call).and_return(refresh_result)
    karafka.produce(trigger.to_json)
  end

  it "refreshes the customer wallets" do
    consumer.consume

    expect(Wallets::RealtimeRefreshService).to have_received(:call).with(
      organization_id: organization.id,
      customer_id: customer.id,
      wallet_codes: [],
      expected_ingested_at: {subscription.id => watermark_ms}
    )
  end

  context "with several triggers for the same customer" do
    before do
      karafka.produce(trigger.merge(last_ingested_at: watermark_ms + 1000, target_wallet_code: "gold").to_json)
    end

    it "refreshes once, at the latest watermark" do
      consumer.consume

      expect(Wallets::RealtimeRefreshService).to have_received(:call).with(
        organization_id: organization.id,
        customer_id: customer.id,
        wallet_codes: ["gold"],
        expected_ingested_at: {subscription.id => watermark_ms + 1000}
      ).once
    end
  end

  context "when realtime usage is off for the organization" do
    let(:realtime_usage_enabled) { "false" }

    it "does not refresh" do
      consumer.consume

      expect(Wallets::RealtimeRefreshService).not_to have_received(:call)
    end
  end

  context "when the organization does not read the clickhouse events store" do
    let(:organization) { create(:organization, feature_flags: ["realtime_usage"]) }

    it "does not refresh" do
      consumer.consume

      expect(Wallets::RealtimeRefreshService).not_to have_received(:call)
    end
  end

  context "when the organization deduplicates its events" do
    let(:organization) do
      create(
        :organization,
        clickhouse_events_store: true,
        clickhouse_deduplication_enabled: true,
        feature_flags: ["realtime_usage"]
      )
    end

    it "does not refresh" do
      consumer.consume

      expect(Wallets::RealtimeRefreshService).not_to have_received(:call)
    end
  end

  context "without an active wallet" do
    let(:wallet_status) { :terminated }

    it "does not refresh" do
      consumer.consume

      expect(Wallets::RealtimeRefreshService).not_to have_received(:call)
    end
  end
end
