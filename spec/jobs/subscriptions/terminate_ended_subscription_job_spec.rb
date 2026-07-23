# frozen_string_literal: true

require "rails_helper"

RSpec.describe Subscriptions::TerminateEndedSubscriptionJob do
  let(:subscription) { create(:subscription) }
  let(:result) { Subscriptions::TerminateService::Result.new }

  before do
    allow(Subscriptions::TerminateService).to receive(:call!).and_call_original
    allow(Subscriptions::TerminateService).to receive(:call)
      .with(subscription:, terminated_at: subscription.ending_at)
      .and_return(result)
  end

  describe "#perform" do
    it "calls the subscription service, pinning termination to ending_at" do
      described_class.perform_now(subscription)

      expect(Subscriptions::TerminateService)
        .to have_received(:call!).with(subscription:, terminated_at: subscription.ending_at)
    end

    context "when the service returns a failure" do
      let(:result) do
        Subscriptions::TerminateService::Result.new.not_found_failure!(resource: "subscription")
      end

      it "raises a FailedResult error" do
        expect { described_class.perform_now(subscription) }
          .to raise_error(BaseService::FailedResult)
      end
    end
  end
end
