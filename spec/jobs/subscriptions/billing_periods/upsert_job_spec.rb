# frozen_string_literal: true

require "rails_helper"

RSpec.describe Subscriptions::BillingPeriods::UpsertJob, job: true do
  subject(:perform) { described_class.perform_now(subscription_id) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:subscription) { create(:subscription, organization:, customer:, plan:, status: :active) }
  let(:subscription_id) { subscription.id }

  before { allow(Subscriptions::BillingPeriods::UpsertService).to receive(:call!).and_call_original }

  it "materializes the periods of the subscription" do
    expect { perform }.to change(SubscriptionBillingPeriod, :count).by(2)

    expect(Subscriptions::BillingPeriods::UpsertService).to have_received(:call!).with(subscription:)
  end

  # The sweep pages over ids, so one can be deleted between the enqueue and the run.
  context "when the subscription no longer exists" do
    let(:subscription_id) { SecureRandom.uuid }

    it "does nothing" do
      expect { perform }.not_to change(SubscriptionBillingPeriod, :count)

      expect(Subscriptions::BillingPeriods::UpsertService).not_to have_received(:call!)
    end
  end

  describe "unique" do
    # until_executed would hold the lock past the raise, so the retry enqueue would be dropped as a
    # duplicate and the refresh lost.
    it "has unique :until_executing constraint" do
      expect(described_class.lock_strategy_class).to eq(ActiveJob::Uniqueness::Strategies::UntilExecuting)
    end
  end

  describe "retry_on" do
    # A lifecycle transaction holds the writer lock until it commits, so a refresh running
    # alongside one loses the race and has to come back rather than drop the write.
    context "when the writer lock cannot be acquired" do
      before do
        allow(Subscriptions::BillingPeriods::UpsertService).to receive(:call!)
          .and_raise(BaseLockService::FailedToAcquireLock, "subscription-billing-periods")
      end

      it "retries" do
        assert_performed_jobs(ApplicationJob::MAX_LOCK_RETRY_ATTEMPTS, only: [described_class]) do
          expect do
            described_class.perform_later(subscription_id)
          end.to raise_error(BaseLockService::FailedToAcquireLock)
        end
      end
    end
  end
end
