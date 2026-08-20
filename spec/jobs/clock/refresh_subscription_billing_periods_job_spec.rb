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
        period_from: 2.hours.ago,
        period_to: 1.hour.ago
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

  # Closed periods are kept, so a sweep driven by "any period that has ended" would come back to
  # every subscription that ever rolled, on every tick.
  context "when the rollover has already been materialized" do
    before do
      create(
        :subscription_billing_period,
        subscription:,
        period_from: 2.hours.ago,
        period_to: 1.hour.ago
      )
      create(
        :subscription_billing_period,
        subscription:,
        period_from: 1.hour.ago + 1.second,
        period_to: 1.month.from_now
      )
      create(
        :subscription_billing_period,
        subscription:,
        period_from: 1.month.from_now + 1.second,
        period_to: 2.months.from_now
      )
    end

    it "enqueues nothing" do
      expect { perform }.not_to have_enqueued_job(Subscriptions::BillingPeriods::UpsertJob)
    end
  end

  context "when the period ended before the lookback window" do
    before do
      create(
        :subscription_billing_period,
        subscription:,
        period_from: 3.months.ago,
        period_to: 2.months.ago
      )
    end

    it "enqueues nothing" do
      expect { perform }.not_to have_enqueued_job(Subscriptions::BillingPeriods::UpsertJob)
    end
  end

  # Its last period has no successor to materialize, so it would otherwise be enqueued on every
  # tick until the window slid past it.
  context "when the subscription is terminated" do
    let(:subscription) do
      create(:subscription, organization:, customer:, plan:, status: :terminated, terminated_at: 1.hour.ago)
    end

    before do
      create(
        :subscription_billing_period,
        subscription:,
        period_from: 2.hours.ago,
        period_to: 1.hour.ago
      )
    end

    it "enqueues nothing" do
      expect { perform }.not_to have_enqueued_job(Subscriptions::BillingPeriods::UpsertJob)
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
