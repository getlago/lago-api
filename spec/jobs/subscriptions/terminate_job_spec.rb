# frozen_string_literal: true

require "rails_helper"

RSpec.describe Subscriptions::TerminateJob do
  let(:subscription) { create(:subscription) }
  let(:timestamp) { Time.zone.now.to_i }

  let(:subscription_service) { instance_double(Subscriptions::TerminateService) }
  let(:result) { BaseService::Result.new }

  it "calls the subscription service" do
    allow(Subscriptions::TerminateService).to receive(:new)
      .with(subscription:)
      .and_return(subscription_service)
    allow(subscription_service).to receive(:terminate_and_start_next)
      .with(timestamp:)
      .and_return(result)

    described_class.perform_now(subscription, timestamp)

    expect(Subscriptions::TerminateService).to have_received(:new)
    expect(subscription_service).to have_received(:terminate_and_start_next)
  end

  context "when result is a failure" do
    let(:result) do
      BaseService::Result.new.not_found_failure!(resource: "subscription")
    end

    it "raises an error" do
      allow(Subscriptions::TerminateService).to receive(:new)
        .with(subscription:)
        .and_return(subscription_service)
      allow(subscription_service).to receive(:terminate_and_start_next)
        .with(timestamp:)
        .and_return(result)

      expect do
        described_class.perform_now(subscription, timestamp)
      end.to raise_error(BaseService::FailedResult)

      expect(Subscriptions::TerminateService).to have_received(:new)
      expect(subscription_service).to have_received(:terminate_and_start_next)
    end
  end

  describe "retry_on" do
    [
      [Customers::FailedToAcquireLock.new("customer-1-prepaid_credit"), 25],
      [ActiveRecord::StaleObjectError.new("Attempted to update a stale object: Wallet."), 25]
    ].each do |error, attempts|
      error_class = error.class

      context "when a #{error_class} error is raised" do
        before do
          allow(Subscriptions::TerminateService).to receive(:new)
            .and_return(subscription_service)
          allow(subscription_service).to receive(:terminate_and_start_next)
            .and_raise(error)
        end

        it "raises a #{error_class.class.name} error and retries" do
          assert_performed_jobs(attempts, only: [described_class]) do
            expect do
              described_class.perform_later(subscription, timestamp)
            end.to raise_error(error_class)
          end
        end
      end
    end
  end
end
