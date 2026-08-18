# frozen_string_literal: true

require "rails_helper"

RSpec.describe Clock::RefreshSubscriptionBillingPeriodsJob, job: true do
  subject(:perform) { described_class.perform_now }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:subscription) { create(:subscription, organization:, customer:, plan:, status: :active) }

  context "with a period that has ended" do
    before do
      create(
        :subscription_billing_period,
        subscription:,
        period_from: 2.months.ago,
        period_to: 1.month.ago
      )
    end

    it "enqueues a refresh for the subscription" do
      expect { perform }.to have_enqueued_job(Subscriptions::BillingPeriods::UpsertJob)
        .with(subscription.id)
    end

    it "chains itself for the next page" do
      expect { perform }.to have_enqueued_job(described_class).with(subscription.id)
    end
  end

  context "with a period that is still open" do
    before do
      create(
        :subscription_billing_period,
        subscription:,
        period_from: 1.day.ago,
        period_to: 1.month.from_now
      )
    end

    it "enqueues nothing" do
      expect { perform }.not_to have_enqueued_job(Subscriptions::BillingPeriods::UpsertJob)
    end

    it "does not chain itself" do
      expect { perform }.not_to have_enqueued_job(described_class)
    end
  end
end
