# frozen_string_literal: true

require "rails_helper"

describe X402::CreditPurchases::ValidateService do
  subject(:result) { described_class.call(connection: x402_connection, params:, verified_payment:) }

  include_context "with an x402 payment"

  let(:plan) { create(:plan, organization:, amount_cents: 0, amount_currency: "USD") }
  let(:wallet_shape) { {name: "Agent credits", rate_amount: "0.001", currency: "USD"} }
  let(:params) { {plan_code: plan.code, wallet_code: "agent_credits", wallet: wallet_shape} }
  let(:verified_payment) { nil }

  context "without a verified payment" do
    it "passes" do
      expect(result).to be_success
    end

    context "without a plan code" do
      let(:params) { super().except(:plan_code) }

      it "refuses the plan code as mandatory" do
        expect(result.error.messages).to eq(plan_code: ["value_is_mandatory"])
      end
    end

    context "with a blank wallet code" do
      let(:params) { super().merge(wallet_code: "") }

      it "refuses the wallet code as mandatory" do
        expect(result.error.messages).to eq(wallet_code: ["value_is_mandatory"])
      end
    end

    context "with an unknown plan code" do
      let(:params) { super().merge(plan_code: "unknown") }

      it "fails with plan_not_found" do
        expect(result.error.error_code).to eq("plan_not_found")
      end
    end

    context "with another organization's plan" do
      let(:plan) { create(:plan, amount_cents: 0, amount_currency: "USD") }

      it "fails with plan_not_found" do
        expect(result.error.error_code).to eq("plan_not_found")
      end
    end

    context "with a deleted plan" do
      let(:plan) { create(:plan, organization:, deleted_at: Time.current) }

      it "fails with plan_not_found" do
        expect(result.error.error_code).to eq("plan_not_found")
      end
    end
  end
end
