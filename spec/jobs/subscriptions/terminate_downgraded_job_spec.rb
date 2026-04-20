# frozen_string_literal: true

require "rails_helper"

RSpec.describe Subscriptions::TerminateDowngradedJob do
  let(:subscription) { create(:subscription) }
  let(:timestamp) { Time.zone.now.to_i }

  let(:subscription_service) { instance_double(Subscriptions::TerminateDowngradedService) }
  let(:result) { BaseService::Result.new }

  it "calls the subscription service" do
    allow(Subscriptions::TerminateDowngradedService).to receive(:new)
      .with(subscription:, timestamp:)
      .and_return(subscription_service)
    allow(subscription_service).to receive(:call)
      .and_return(result)

    described_class.perform_now(subscription, timestamp)

    expect(Subscriptions::TerminateDowngradedService).to have_received(:new)
    expect(subscription_service).to have_received(:call)
  end

  context "when result is a failure" do
    let(:result) do
      BaseService::Result.new.not_found_failure!(resource: "subscription")
    end

    it "raises an error" do
      allow(Subscriptions::TerminateDowngradedService).to receive(:new)
        .with(subscription:, timestamp:)
        .and_return(subscription_service)
      allow(subscription_service).to receive(:call)
        .and_return(result)

      expect do
        described_class.perform_now(subscription, timestamp)
      end.to raise_error(BaseService::FailedResult)

      expect(Subscriptions::TerminateDowngradedService).to have_received(:new)
      expect(subscription_service).to have_received(:call)
    end
  end
end
