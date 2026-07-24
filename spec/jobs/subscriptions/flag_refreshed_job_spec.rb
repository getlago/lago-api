# frozen_string_literal: true

require "rails_helper"

RSpec.describe Subscriptions::FlagRefreshedJob do
  let(:subscription_id) { SecureRandom.uuid }

  it_behaves_like "a configurable queue", "alerts_high_priority", "SIDEKIQ_ALERTS" do
    let(:arguments) { subscription_id }
  end

  describe "#perform" do
    it "calls the subscriptions flag refreshed service" do
      allow(Subscriptions::FlagRefreshedService).to receive(:call!)

      described_class.perform_now(subscription_id)

      expect(Subscriptions::FlagRefreshedService).to have_received(:call!)
        .with(subscription_id, event_ingested_at: nil)
    end

    context "with an event ingestion timestamp" do
      let(:event_ingested_at) { 30.seconds.ago.to_f }

      it "passes the timestamp to the service" do
        allow(Subscriptions::FlagRefreshedService).to receive(:call!)

        described_class.perform_now(subscription_id, event_ingested_at)

        expect(Subscriptions::FlagRefreshedService).to have_received(:call!)
          .with(subscription_id, event_ingested_at:)
      end
    end
  end
end
