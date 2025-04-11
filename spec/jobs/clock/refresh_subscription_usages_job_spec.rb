# frozen_string_literal: true

require "rails_helper"

describe Clock::RefreshSubscriptionUsagesJob, job: true do
  subject { described_class }

  describe ".perform" do
    let(:organization) { create(:organization) }

    let(:customer1) { create(:customer, organization:) }
    let(:subscription1) { create(:subscription, customer: customer1) }
    let(:usage_activity1) do
      create(:subscription_usage_activity, organization:, subscription: subscription1, recalculate_current_usage: true)
    end

    let(:customer2) { create(:customer, organization:) }
    let(:subscription2) { create(:subscription, customer: customer2) }
    let(:usage_activity2) do
      create(:subscription_usage_activity, organization:, subscription: subscription2, recalculate_current_usage: true)
    end

    let(:customer3) { create(:customer, organization:) }
    let(:subscription3) { create(:subscription, customer: customer3) }
    let(:usage_activity3) do
      create(:subscription_usage_activity, organization:, subscription: subscription3, recalculate_current_usage: false)
    end

    before do
      usage_activity1
      usage_activity2
      usage_activity3
    end

    context "when freemium" do
      it "does not call the refresh service" do
        described_class.perform_now

        expect(Subscriptions::RecalculateUsageJob).not_to have_been_enqueued.with(subscription1)
        expect(Subscriptions::RecalculateUsageJob).not_to have_been_enqueued.with(subscription2)
        expect(Subscriptions::RecalculateUsageJob).not_to have_been_enqueued.with(subscription3)
      end
    end

    context "when only premium" do
      around { |test| lago_premium!(&test) }

      it "does not enqueue any job" do
        described_class.perform_now

        expect(Subscriptions::RecalculateUsageJob).not_to have_been_enqueued.with(subscription1)
        expect(Subscriptions::RecalculateUsageJob).not_to have_been_enqueued.with(subscription2)
        expect(Subscriptions::RecalculateUsageJob).not_to have_been_enqueued.with(subscription3)
      end
    end

    context "when premium & with the progressive_billing premium_integration is enabled" do
      let(:organization) { create(:organization, premium_integrations: ["progressive_billing"]) }

      around { |test| lago_premium!(&test) }

      it "enqueues a job for every usage that needs to be recalculated" do
        described_class.perform_now

        expect(Subscriptions::RecalculateUsageJob).to have_been_enqueued.with(subscription1)
        expect(Subscriptions::RecalculateUsageJob).to have_been_enqueued.with(subscription2)
        expect(Subscriptions::RecalculateUsageJob).not_to have_been_enqueued.with(subscription3)
      end
    end

    context "when premium & with the lifetime_usage premium_integration is enabled" do
      let(:organization) { create(:organization, premium_integrations: ["lifetime_usage"]) }

      around { |test| lago_premium!(&test) }

      it "enqueues a job for every usage that needs to be recalculated" do
        described_class.perform_now

        expect(Subscriptions::RecalculateUsageJob).to have_been_enqueued.with(subscription1)
        expect(Subscriptions::RecalculateUsageJob).to have_been_enqueued.with(subscription2)
        expect(Subscriptions::RecalculateUsageJob).not_to have_been_enqueued.with(subscription3)
      end
    end

    context "when premium & with the alerting_total_usage premium_integration is enabled" do
      let(:organization) { create(:organization, premium_integrations: ["alerting_total_usage"]) }

      around { |test| lago_premium!(&test) }

      it "enqueues a job for every usage that needs to be recalculated" do
        described_class.perform_now

        expect(Subscriptions::RecalculateUsageJob).to have_been_enqueued.with(subscription1)
        expect(Subscriptions::RecalculateUsageJob).to have_been_enqueued.with(subscription2)
        expect(Subscriptions::RecalculateUsageJob).not_to have_been_enqueued.with(subscription3)
      end
    end
  end
end
