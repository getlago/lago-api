# frozen_string_literal: true

require "rails_helper"

RSpec.describe Subscriptions::ActivateService do
  subject(:result) { described_class.call(subscription:, timestamp:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:subscription) { create(:subscription, :pending, organization:, customer:, plan:, subscription_at: Time.current) }
  let(:timestamp) { Time.current }

  it "activates the subscription" do
    freeze_time do
      expect(result.subscription).to be_active
      expect(result.subscription.started_at).to eq(Time.current)
      expect(result.subscription.activated_at).to eq(Time.current)
    end
  end

  it "sends a subscription.started webhook" do
    result

    expect(SendWebhookJob).to have_been_enqueued.with("subscription.started", subscription)
  end

  it "produces a subscription.started activity log" do
    result

    expect(Utils::ActivityLog).to have_produced("subscription.started").with(subscription)
  end

  context "when subscription has fixed charges" do
    let(:add_on) { create(:add_on, organization:) }
    let(:fixed_charge) { create(:fixed_charge, plan:, add_on:) }

    before { fixed_charge }

    it "emits fixed charge events" do
      expect { result }.to change(FixedChargeEvent, :count).by(1)
    end
  end

  context "when subscription should sync with hubspot" do
    let(:customer) { create(:customer, :with_hubspot_integration, organization:) }

    it "enqueues hubspot sync job" do
      result

      expect(Integrations::Aggregator::Subscriptions::Hubspot::UpdateJob)
        .to have_been_enqueued.with(subscription:)
    end
  end

  context "when plan is pay in advance and not in trial" do
    let(:plan) { create(:plan, organization:, pay_in_advance: true) }

    it "enqueues BillSubscriptionJob" do
      result

      expect(BillSubscriptionJob).to have_been_enqueued
        .with([subscription], anything, invoicing_reason: :subscription_starting, skip_charges: true)
    end
  end

  context "when plan is pay in arrears with pay-in-advance fixed charges" do
    let(:plan) { create(:plan, organization:, pay_in_advance: false) }
    let(:add_on) { create(:add_on, organization:) }

    before { create(:fixed_charge, plan:, add_on:, pay_in_advance: true) }

    it "enqueues CreatePayInAdvanceFixedChargesJob" do
      result

      expect(Invoices::CreatePayInAdvanceFixedChargesJob).to have_been_enqueued
    end
  end

  context "when plan is pay in advance with trial period" do
    let(:plan) { create(:plan, organization:, pay_in_advance: true, trial_period: 30) }

    it "does not enqueue BillSubscriptionJob" do
      result

      expect(BillSubscriptionJob).not_to have_been_enqueued
    end
  end

  context "when subscription is already active" do
    let(:subscription) { create(:subscription, organization:, customer:, plan:) }

    it "returns the subscription without changes" do
      expect(result.subscription).to be_active
      expect(SendWebhookJob).not_to have_been_enqueued
    end
  end
end
