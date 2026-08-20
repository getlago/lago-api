# frozen_string_literal: true

require "rails_helper"

RSpec.describe Subscriptions::BillingPeriods::DetectMissingService do
  subject(:result) { described_class.call(organization:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:subscription) { create(:subscription, organization:, customer:, plan:, status: :active) }

  context "when an active subscription has no covering period" do
    before { subscription }

    it "enqueues a refresh for it" do
      expect { result }.to have_enqueued_job(Subscriptions::BillingPeriods::UpsertJob)
        .with(subscription.id)
    end

    it "counts and reports it" do
      allow(Rails.logger).to receive(:warn)

      expect(result.missing_count).to eq(1)
      expect(Rails.logger).to have_received(:warn)
        .with(/1 active subscriptions without a covering period/)
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

    it "enqueues nothing and reports nothing" do
      allow(Rails.logger).to receive(:warn)

      expect { result }.not_to have_enqueued_job(Subscriptions::BillingPeriods::UpsertJob)
      expect(result.missing_count).to eq(0)
      expect(Rails.logger).not_to have_received(:warn)
    end
  end

  context "when the subscription is not active" do
    before { create(:subscription, :pending, organization:, customer:, plan:) }

    it "ignores it" do
      expect(result.missing_count).to eq(0)
    end
  end

  # The writer skips a plan without an interval, so such a subscription is not missing anything and
  # would otherwise be enqueued and reported every night, forever.
  context "when the plan has no interval" do
    let(:plan) { create(:plan, organization:, interval: nil, pricing_type: :product_catalog) }

    before { subscription }

    it "neither enqueues nor reports" do
      allow(Rails.logger).to receive(:warn)

      expect { result }.not_to have_enqueued_job(Subscriptions::BillingPeriods::UpsertJob)
      expect(result.missing_count).to eq(0)
      expect(Rails.logger).not_to have_received(:warn)
    end
  end

  # Its first period opens at the start, so nothing covers now until then.
  context "when the subscription has yet to start" do
    let(:subscription) do
      create(
        :subscription,
        organization:, customer:, plan:,
        status: :active,
        started_at: 2.hours.from_now
      )
    end

    before { subscription }

    it "ignores it" do
      expect(result.missing_count).to eq(0)
    end
  end

  context "when the subscription belongs to another organization" do
    before { create(:subscription, status: :active) }

    it "ignores it" do
      expect(result.missing_count).to eq(0)
    end
  end

  context "when the feature flag is disabled" do
    let(:organization) { create(:organization, feature_flags: []) }

    before { subscription }

    # Otherwise every active subscription of a disabled organization is enqueued and reported as
    # missing, every night.
    it "neither enqueues nor reports" do
      allow(Rails.logger).to receive(:warn)

      expect { result }.not_to have_enqueued_job(Subscriptions::BillingPeriods::UpsertJob)
      expect(result.missing_count).to eq(0)
      expect(Rails.logger).not_to have_received(:warn)
    end
  end
end
