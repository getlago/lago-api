# frozen_string_literal: true

require "rails_helper"

RSpec.describe Subscriptions::ActivateService do
  subject(:result) { described_class.call(subscription:, timestamp:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:subscription) { create(:subscription, :pending, organization:, customer:, plan:, subscription_at: Time.current) }
  let(:timestamp) { Time.current }

  context "when subscription is pending without activation rules" do
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

    it "does not enqueue billing jobs" do
      result

      expect(BillSubscriptionJob).not_to have_been_enqueued
      expect(Invoices::CreatePayInAdvanceFixedChargesJob).not_to have_been_enqueued
    end

    context "when subscription has fixed charges" do
      let(:add_on) { create(:add_on, organization:) }

      before { create(:fixed_charge, plan:, add_on:) }

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

      it "enqueues BillSubscriptionJob with skip_charges true" do
        result

        expect(BillSubscriptionJob).to have_been_enqueued
          .with([subscription], anything, invoicing_reason: :subscription_starting, skip_charges: true)
      end

      it "does not enqueue CreatePayInAdvanceFixedChargesJob" do
        result

        expect(Invoices::CreatePayInAdvanceFixedChargesJob).not_to have_been_enqueued
      end
    end

    context "when plan is pay in advance with pay-in-advance fixed charges" do
      let(:plan) { create(:plan, organization:, pay_in_advance: true) }
      let(:add_on) { create(:add_on, organization:) }

      before { create(:fixed_charge, plan:, add_on:, pay_in_advance: true) }

      it "enqueues BillSubscriptionJob but not CreatePayInAdvanceFixedChargesJob" do
        result

        expect(BillSubscriptionJob).to have_been_enqueued
        expect(Invoices::CreatePayInAdvanceFixedChargesJob).not_to have_been_enqueued
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

    context "when plan is pay in arrears with non-pay-in-advance fixed charges" do
      let(:plan) { create(:plan, organization:, pay_in_advance: false) }
      let(:add_on) { create(:add_on, organization:) }

      before { create(:fixed_charge, plan:, add_on:, pay_in_advance: false) }

      it "does not enqueue any billing job" do
        result

        expect(BillSubscriptionJob).not_to have_been_enqueued
        expect(Invoices::CreatePayInAdvanceFixedChargesJob).not_to have_been_enqueued
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

        it "does not enqueue BillSubscriptionJob" do
          result

          expect(BillSubscriptionJob).not_to have_been_enqueued
        end
      end
    end
  end

  context "when subscription is pending with activation rules (payment, pay-in-advance plan)" do
    let(:plan) { create(:plan, organization:, pay_in_advance: true) }
    let(:subscription) do
      create(:subscription, :pending, :with_activation_rules,
        activation_rules_config: [{type: "payment", timeout_hours: 48}],
        organization:, customer:, plan:, subscription_at: Time.current)
    end

    it "evaluates rules and marks the subscription as incomplete" do
      expect(result.subscription).to be_incomplete
      expect(result.subscription.started_at).to be_present
      expect(subscription.activation_rules.sole).to be_pending
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

    it "does not sync with hubspot" do
      result

      expect(Integrations::Aggregator::Subscriptions::Hubspot::UpdateJob).not_to have_been_enqueued
    end

    it "enqueues BillSubscriptionJob with skip_charges" do
      result

      expect(BillSubscriptionJob).to have_been_enqueued
        .with([subscription], anything, invoicing_reason: :subscription_starting, skip_charges: true)
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
  end

  context "when subscription is pending with activation rules that evaluate to not_applicable" do
    let(:plan) { create(:plan, organization:, pay_in_advance: false) }
    let(:subscription) do
      create(:subscription, :pending, :with_activation_rules,
        activation_rules_config: [{type: "payment", timeout_hours: 48}],
        organization:, customer:, plan:, subscription_at: Time.current)
    end

    it "evaluates rules as not_applicable and activates normally" do
      expect(result.subscription).to be_active
      expect(subscription.activation_rules.sole).to be_not_applicable
    end

    it "sends a subscription.started webhook" do
      result

      expect(SendWebhookJob).to have_been_enqueued.with("subscription.started", subscription)
    end
  end

  context "when subscription is incomplete with satisfied payment rule (post-payment activation)" do
    let(:plan) { create(:plan, organization:, pay_in_advance: true) }
    let(:subscription) do
      create(:subscription, :incomplete, :with_activation_rules,
        activation_rules_config: [{type: "payment", timeout_hours: 48, status: "satisfied"}],
        organization:, customer:, plan:)
    end

    it "activates the subscription" do
      freeze_time do
        expect(result.subscription).to be_active
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

    it "does not enqueue billing jobs (already billed during gating)" do
      result

      expect(BillSubscriptionJob).not_to have_been_enqueued
      expect(Invoices::CreatePayInAdvanceFixedChargesJob).not_to have_been_enqueued
    end

    it "does not emit fixed charge events (already emitted during gating)" do
      add_on = create(:add_on, organization:)
      create(:fixed_charge, plan:, add_on:)

      expect { result }.not_to change(FixedChargeEvent, :count)
    end

    context "when subscription should sync with hubspot" do
      let(:customer) { create(:customer, :with_hubspot_integration, organization:) }

      it "enqueues hubspot sync job" do
        result

        expect(Integrations::Aggregator::Subscriptions::Hubspot::UpdateJob)
          .to have_been_enqueued.with(subscription:)
      end
    end
  end

  context "when subscription is incomplete with no payment rules (future non-payment rule resolved)" do
    let(:plan) { create(:plan, organization:, pay_in_advance: true) }
    let(:subscription) { create(:subscription, :incomplete, organization:, customer:, plan:) }

    it "activates and bills the subscription" do
      result

      expect(result.subscription).to be_active
      expect(BillSubscriptionJob).to have_been_enqueued
    end
  end

  context "when subscription is incomplete with a failed payment rule" do
    let(:plan) { create(:plan, organization:, pay_in_advance: true) }
    let(:subscription) do
      create(:subscription, :incomplete, :with_activation_rules,
        activation_rules_config: [{type: :payment, timeout_hours: 48, status: :failed}],
        organization:, customer:, plan:)
    end

    it "does not activate the subscription" do
      result

      expect(subscription.reload).to be_incomplete
      expect(SendWebhookJob).not_to have_been_enqueued
      expect(BillSubscriptionJob).not_to have_been_enqueued
    end
  end

  context "when subscription is already active" do
    let(:subscription) { create(:subscription, organization:, customer:, plan:) }

    it "returns early without changes" do
      result

      expect(subscription.reload).to be_active
      expect(SendWebhookJob).not_to have_been_enqueued
      expect(BillSubscriptionJob).not_to have_been_enqueued
      expect(Invoices::CreatePayInAdvanceFixedChargesJob).not_to have_been_enqueued
    end
  end

  context "when subscription is already gated (incomplete with pending rules)" do
    let(:subscription) do
      create(:subscription, :incomplete, :with_activation_rules,
        activation_rules_config: [{type: "payment", timeout_hours: 48, status: "pending"}],
        organization:, customer:, plan:)
    end

    it "returns early without changes" do
      result

      expect(subscription.reload).to be_incomplete
      expect(SendWebhookJob).not_to have_been_enqueued
    end
  end
end
