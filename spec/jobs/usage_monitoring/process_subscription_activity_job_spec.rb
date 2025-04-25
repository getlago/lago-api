# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageMonitoring::ProcessSubscriptionActivityJob, type: :job do
  describe "#perform" do
    let(:subscription_activity) { create(:subscription_activity) }
    let(:subscription_activity_id) { subscription_activity.id }

    before do
      allow(UsageMonitoring::ProcessSubscriptionActivityService).to receive(:call!)
    end

    it "calls the ProcessSubscriptionActivityService with the subscription activity" do
      described_class.perform_now(subscription_activity_id)
      expect(UsageMonitoring::ProcessSubscriptionActivityService).to have_received(:call!).with(subscription_activity:)
    end

    context "when the subscription activity does not exist" do
      let(:subscription_activity_id) { 9_999_999_999_999 }

      it "does not call the ProcessSubscriptionActivityService" do
        expect(UsageMonitoring::ProcessSubscriptionActivityService).not_to have_received(:call!)
        described_class.perform_now(subscription_activity_id)
      end
    end
  end
end
