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
end
