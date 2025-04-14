# frozen_string_literal: true

require "rails_helper"

RSpec.describe Subscriptions::RecalculateUsageJob, type: :job do
  describe "#perform" do
    let(:subscription) { create(:subscription) }

    it "calls the subscriptions flag refreshed job" do
      allow(Subscriptions::RecalculateUsageService).to receive(:call!)

      described_class.perform_now(subscription)

      expect(Subscriptions::RecalculateUsageService).to have_received(:call!)
        .with(subscription:)
    end
  end
end
