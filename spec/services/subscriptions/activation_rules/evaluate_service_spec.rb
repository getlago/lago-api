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
      expect(rule.reload.status).to eq("pending")
    end
  end

  context "when subscription has no activation rules" do
    it "returns success without changes" do
      expect(result).to be_success
    end
  end
end
