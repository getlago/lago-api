# frozen_string_literal: true

require "rails_helper"

RSpec.describe Clock::ConsumeSubscriptionRefreshedQueueJob do
  subject(:refresh_jobs) { described_class }

  describe "#perform" do
    before { allow(Subscriptions::ConsumeSubscriptionRefreshedQueueService).to receive(:call!) }

    it "consumes the subscription refresh requests from the queue" do
      refresh_jobs.perform_now

      expect(Subscriptions::ConsumeSubscriptionRefreshedQueueService).to have_received(:call!)
    end
  end
end
