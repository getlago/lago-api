# frozen_string_literal: true

require "rails_helper"

RSpec.describe Subscriptions::GatedActivationService do
  subject(:result) { described_class.call(subscription:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:, pay_in_advance: true) }
  let(:subscription) do
    create(:subscription, :pending, :with_activation_rules,
      activation_rules_config: [{type: "payment", timeout_hours: 48, status: "pending"}],
      organization:, customer:, plan:, subscription_at: Time.current)
  end

  it "marks the subscription as incomplete" do
    expect(result.subscription).to be_incomplete
    expect(result.subscription.started_at).to be_present
  end

  it "emits fixed charge events" do
    add_on = create(:add_on, organization:)
    create(:fixed_charge, plan:, add_on:)

    expect { result }.to change(FixedChargeEvent, :count).by(1)
  end

  it "sends a subscription.incomplete webhook" do
    result

    expect(SendWebhookJob).to have_been_enqueued.with("subscription.incomplete", subscription)
  end

  it "produces a subscription.incomplete activity log" do
    result

    expect(Utils::ActivityLog).to have_produced("subscription.incomplete").with(subscription)
  end

  context "when plan is pay in advance and not in trial" do
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

    it "does not enqueue BillSubscriptionJob" do
      result

      expect(BillSubscriptionJob).not_to have_been_enqueued
    end
  end

  context "when plan is pay in advance with trial period" do
    let(:plan) { create(:plan, organization:, pay_in_advance: true, trial_period: 30) }

    it "does not enqueue BillSubscriptionJob" do
      result

      expect(BillSubscriptionJob).not_to have_been_enqueued
    end

    context "when plan has pay-in-advance fixed charges" do
      let(:add_on) { create(:add_on, organization:) }

      before { create(:fixed_charge, plan:, add_on:, pay_in_advance: true) }

      it "enqueues CreatePayInAdvanceFixedChargesJob" do
        result

        expect(Invoices::CreatePayInAdvanceFixedChargesJob).to have_been_enqueued
      end
    end
  end

  context "when subscription has no pending rules" do
    let(:subscription) do
      create(:subscription, :pending, :with_activation_rules,
        activation_rules_config: [{type: "payment", timeout_hours: 48, status: "not_applicable"}],
        organization:, customer:, plan:, subscription_at: Time.current)
    end

    it "returns early without changes" do
      result

      expect(subscription.reload).to be_pending
      expect(SendWebhookJob).not_to have_been_enqueued
    end
  end

  context "when subscription is already active" do
    let(:subscription) { create(:subscription, organization:, customer:, plan:) }

    it "returns early without changes" do
      result

      expect(subscription.reload).to be_active
      expect(SendWebhookJob).not_to have_been_enqueued
    end
  end

  context "when subscription is already incomplete" do
    let(:subscription) do
      create(:subscription, :incomplete, :with_activation_rules,
        activation_rules_config: [{type: "payment", timeout_hours: 48, status: "pending"}],
        organization:, customer:, plan:)
    end

    it "returns early without changes" do
      expect(SendWebhookJob).not_to have_been_enqueued
    end
  end
end
