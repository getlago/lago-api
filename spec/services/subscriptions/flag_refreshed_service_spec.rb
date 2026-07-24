# frozen_string_literal: true

require "rails_helper"

RSpec.describe Subscriptions::FlagRefreshedService, :premium do
  let(:organization) { create(:organization, premium_integrations: %w[lifetime_usage]) }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, customer:) }

  before do
    allow(UsageMonitoring::TrackSubscriptionActivityService).to receive(:call).and_call_original
    create(:wallet, customer:, organization:)
  end

  describe "#call" do
    subject(:result) { described_class.call(subscription.id) }

    it "marks customer as awaiting wallet refresh" do
      expect { subject }.to change { customer.reload.awaiting_wallet_refresh }.from(false).to(true)
      expect(result).to be_success
    end

    it "tracks subscription activity" do
      subject
      expect(result).to be_success
      expect(subscription.subscription_activity).to be_present
      expected_date = Time.current.in_time_zone(customer.applicable_timezone).to_date
      expect(UsageMonitoring::TrackSubscriptionActivityService).to have_received(:call)
        .with(subscription:, date: expected_date, event_ingested_at: nil)
    end

    context "when an event ingestion timestamp is provided" do
      subject(:result) { described_class.call(subscription.id, event_ingested_at:) }

      let(:event_ingested_at) { 5.minutes.ago.to_f }

      it "propagates the timestamp to the wallet refresh flag and the subscription activity" do
        expect { subject }.to change { customer.reload.wallet_refresh_requested_at&.to_f }
          .from(nil).to(be_within(0.001).of(event_ingested_at))

        expect(result).to be_success
        expected_date = Time.current.in_time_zone(customer.applicable_timezone).to_date
        expect(UsageMonitoring::TrackSubscriptionActivityService).to have_received(:call)
          .with(subscription:, date: expected_date, event_ingested_at: Time.zone.at(event_ingested_at))
      end
    end
  end
end
