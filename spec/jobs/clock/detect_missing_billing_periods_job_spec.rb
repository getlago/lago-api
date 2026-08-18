# frozen_string_literal: true

require "rails_helper"

RSpec.describe Clock::DetectMissingBillingPeriodsJob, job: true do
  subject(:perform) { described_class.perform_now }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:subscription) { create(:subscription, organization:, customer:, plan:, status: :active) }

  context "when an active subscription has no covering period" do
    before { subscription }

    it "enqueues a refresh for it" do
      expect { perform }.to have_enqueued_job(Subscriptions::BillingPeriods::UpsertJob)
        .with(subscription.id)
    end

    it "reports how many were missing" do
      allow(Rails.logger).to receive(:warn)

      perform

      expect(Rails.logger).to have_received(:warn).with(/1 active subscriptions without a covering period/)
    end
  end

  context "when the subscription has a covering period" do
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
  end

  describe "pruning" do
    let(:grace_period) { Subscriptions::BillingPeriods::UpsertService::TERMINATED_GRACE_PERIOD }

    it "deletes periods that ended beyond the grace window" do
      stale = create(
        :subscription_billing_period,
        subscription:,
        period_from: grace_period.ago - 2.months,
        period_to: grace_period.ago - 1.day
      )

      perform

      expect(SubscriptionBillingPeriod.where(id: stale.id)).to be_empty
    end

    it "keeps periods that ended inside the grace window" do
      recent = create(
        :subscription_billing_period,
        subscription:,
        period_from: 2.days.ago,
        period_to: 1.day.ago
      )

      perform

      expect(SubscriptionBillingPeriod.where(id: recent.id)).to be_present
    end
  end
end
