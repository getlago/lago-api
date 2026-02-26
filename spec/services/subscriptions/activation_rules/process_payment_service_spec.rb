# frozen_string_literal: true

require "rails_helper"

RSpec.describe Subscriptions::ActivationRules::ProcessPaymentService do
  subject(:result) { described_class.call(invoice:, payment_status:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:subscription) { create(:subscription, :activating, customer:, plan:, organization:) }
  let(:invoice) { create(:invoice, customer:, organization:) }

  let!(:rule) do
    create(:subscription_activation_rule, subscription:, organization:, rule_type: "payment_required", status: "pending")
  end

  before do
    create(:invoice_subscription, invoice:, subscription:)
  end

  describe "#call" do
    context "when payment succeeded" do
      let(:payment_status) { :succeeded }

      it "satisfies the rule and triggers activation" do
        allow(Subscriptions::ActivationRules::TryActivateService).to receive(:call!).and_return(BaseService::Result.new)

        expect(result).to be_success
        expect(rule.reload.status).to eq("satisfied")
        expect(Subscriptions::ActivationRules::TryActivateService).to have_received(:call!)
          .with(subscription:, invoice:)
      end
    end

    context "when payment failed" do
      let(:payment_status) { :failed }

      it "marks the rule as failed" do
        expect(result).to be_success
        expect(rule.reload.status).to eq("failed")
      end
    end

    context "when subscription is not activating" do
      let(:subscription) { create(:subscription, customer:, plan:, organization:) }
      let(:payment_status) { :succeeded }

      it "returns early without processing" do
        expect(result).to be_success
        expect(rule.reload.status).to eq("pending")
      end
    end

    context "when rule is already satisfied" do
      let(:payment_status) { :succeeded }

      before { rule.update!(status: "satisfied") }

      it "returns early without processing" do
        expect(result).to be_success
        expect(rule.reload.status).to eq("satisfied")
      end
    end

    context "when rule is in failed status" do
      let(:payment_status) { :succeeded }

      before { rule.update!(status: "failed") }

      it "processes the retry and satisfies the rule" do
        allow(Subscriptions::ActivationRules::TryActivateService).to receive(:call!).and_return(BaseService::Result.new)

        expect(result).to be_success
        expect(rule.reload.status).to eq("satisfied")
        expect(Subscriptions::ActivationRules::TryActivateService).to have_received(:call!)
      end
    end
  end
end
