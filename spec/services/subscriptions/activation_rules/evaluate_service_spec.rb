# frozen_string_literal: true

require "rails_helper"

RSpec.describe Subscriptions::ActivationRules::EvaluateService do
  subject(:result) { described_class.call(subscription:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:, pay_in_advance: true) }
  let(:subscription) { create(:subscription, :incomplete, organization:, customer:, plan:) }

  context "when subscription has a payment activation rule" do
    let(:rule) { create(:payment_subscription_activation_rule, subscription:) }

    before { rule }

    it "delegates to Payment::EvaluateService" do
      expect(result).to be_success
      expect(result.rules.first).to be_pending
    end
  end

  context "when subscription has no activation rules" do
    it "returns success without changes" do
      expect(result).to be_success
      expect(result.rules).to be_empty
    end
  end

  context "when all rules are satisfied" do
    let(:rule) { create(:payment_subscription_activation_rule, subscription:, status: "satisfied") }

    before { rule }

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
  end

  context "when a rule has failed" do
    let(:rule) { create(:payment_subscription_activation_rule, subscription:, status: "failed") }

    before { rule }

    it "cancels the subscription" do
      expect(result.subscription).to be_canceled
    end

    it "sends a subscription.canceled webhook" do
      result

      expect(SendWebhookJob).to have_been_enqueued.with("subscription.canceled", subscription)
    end
  end

  context "when rules are still pending" do
    let(:rule) { create(:payment_subscription_activation_rule, subscription:, status: "pending") }

    before { rule }

    it "does not change subscription status" do
      expect(result.subscription).to be_incomplete
    end
  end
end
