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

    it "evaluates the rule and delegates to ResolveSubscriptionStatusService" do
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

  context "when all rules are already satisfied" do
    let(:rule) { create(:payment_subscription_activation_rule, subscription:, status: "satisfied") }

    before { rule }

    it "activates the subscription via ResolveSubscriptionStatusService" do
      allow(Subscriptions::ActivationRules::ResolveSubscriptionStatusService).to receive(:call).and_call_original

      expect(result.subscription).to be_active
      expect(Subscriptions::ActivationRules::ResolveSubscriptionStatusService).to have_received(:call).with(subscription:)
    end
  end
end
