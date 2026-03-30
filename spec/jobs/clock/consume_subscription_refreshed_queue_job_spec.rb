# frozen_string_literal: true

require "rails_helper"

RSpec.describe Clock::ConsumeSubscriptionRefreshedQueueJob do
  subject(:refresh_jobs) { described_class }

  describe "#perform" do
    before do
      allow(Subscriptions::ConsumeSubscriptionRefreshedQueueService).to receive(:call!)
      allow(Subscriptions::ConsumeSubscriptionRefreshedQueueV2Service).to receive(:call!)
    end

    it "consumes the legacy queue by default" do
      refresh_jobs.perform_now

      expect(Subscriptions::ConsumeSubscriptionRefreshedQueueService).to have_received(:call!)
    end

    it "consumes the legacy queue with v1 argument" do
      refresh_jobs.perform_now("v1")

      expect(Subscriptions::ConsumeSubscriptionRefreshedQueueService).to have_received(:call!)
    end

    it "consumes the v2 sorted set queue with v2 argument" do
      refresh_jobs.perform_now("v2")

      expect(Subscriptions::ConsumeSubscriptionRefreshedQueueV2Service).to have_received(:call!)
    end
  end
end
