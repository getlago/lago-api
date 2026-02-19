# frozen_string_literal: true

require "rails_helper"

RSpec.describe Subscriptions::TerminateEndedSubscriptionJob do
  let(:subscription) { create(:subscription) }
  let(:result) { BaseService::Result.new }

  before do
    allow(Subscriptions::TerminateService).to receive(:call)
      .with(subscription:)
      .and_return(result)
  end

  describe "#perform" do
    it "calls the subscription service" do
      described_class.perform_now(subscription)

      expect(Subscriptions::TerminateService).to have_received(:call).with(subscription:)
    end

    context "when the service returns a failure" do
      let(:result) do
        BaseService::Result.new.not_found_failure!(resource: "subscription")
      end

      it "raises a FailedResult error" do
        expect { described_class.perform_now(subscription) }
          .to raise_error(BaseService::FailedResult)
      end
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
          allow(Subscriptions::TerminateService).to receive(:call)
            .and_raise(error)
        end

        it "raises a #{error_class.name} error and retries" do
          assert_performed_jobs(attempts, only: [described_class]) do
            expect do
              described_class.perform_later(subscription)
            end.to raise_error(error_class)
          end
        end
      end
    end
  end
end
