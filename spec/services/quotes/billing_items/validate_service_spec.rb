# frozen_string_literal: true

require "rails_helper"

RSpec.describe Quotes::BillingItems::ValidateService, type: :service do
  subject(:result) { described_class.call(organization:, order_type:, billing_items:) }

  let(:organization) { create(:organization) }
  let(:plan) { create(:plan, organization:) }
  let(:add_on) { create(:add_on, organization:) }
  let(:coupon) { create(:coupon, organization:) }

  describe "subscription_creation order type" do
    let(:order_type) { "subscription_creation" }

    context "with valid plans" do
      let(:billing_items) { {"plans" => [{"plan_id" => plan.id}]} }

      it "returns success with normalized billing_items" do
        expect(result).to be_success
        expect(result.billing_items["plans"].first["id"]).to start_with("qtp_")
        expect(result.billing_items["plans"].first["plan_id"]).to eq(plan.id)
      end
    end

    context "when plan_id is missing" do
      let(:billing_items) { {"plans" => [{}]} }

      it "returns validation failure" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages[:billing_items]).to include("plans[0].plan_id is required")
      end
    end

    context "when plan does not belong to organization" do
      let(:billing_items) { {"plans" => [{"plan_id" => create(:plan).id}]} }

      it "returns validation failure" do
        expect(result).not_to be_success
        expect(result.error.messages[:billing_items]).to include("plans[0].plan_id: plan not found in organization")
      end
    end

    context "with add_ons (not allowed for subscription type)" do
      let(:billing_items) { {"add_ons" => [{"add_on_id" => add_on.id, "name" => "Test"}]} }

      it "returns validation failure" do
        expect(result).not_to be_success
        expect(result.error.messages[:billing_items]).to include("add_ons not allowed for subscription order type")
      end
    end

    context "with valid coupons" do
      let(:billing_items) { {"coupons" => [{"coupon_id" => coupon.id, "coupon_type" => "fixed_amount"}]} }

      it "returns success with normalized billing_items" do
        expect(result).to be_success
        expect(result.billing_items["coupons"].first["id"]).to start_with("qtc_")
      end
    end

    context "when coupon_id is missing" do
      let(:billing_items) { {"coupons" => [{"coupon_type" => "fixed_amount"}]} }

      it "returns validation failure" do
        expect(result).not_to be_success
        expect(result.error.messages[:billing_items]).to include("coupons[0].coupon_id is required")
      end
    end

    context "when coupon_type is invalid" do
      let(:billing_items) { {"coupons" => [{"coupon_id" => coupon.id, "coupon_type" => "invalid"}]} }

      it "returns validation failure" do
        expect(result).not_to be_success
        expect(result.error.messages[:billing_items]).to include("coupons[0].coupon_type is invalid")
      end
    end

    context "with valid wallet_credits" do
      let(:billing_items) { {"wallet_credits" => [{"amount" => "100"}]} }

      it "returns success with normalized billing_items" do
        expect(result).to be_success
        expect(result.billing_items["wallet_credits"].first["id"]).to start_with("qtw_")
      end
    end

    context "with wallet_credits including recurring_transaction_rules" do
      let(:billing_items) do
        {"wallet_credits" => [{"amount" => "100", "recurring_transaction_rules" => [{"trigger" => "interval"}]}]}
      end

      it "assigns ids to recurring rules" do
        expect(result).to be_success
        expect(result.billing_items["wallet_credits"].first["recurring_transaction_rules"].first["id"]).to start_with("qtrr_")
      end
    end
  end

  describe "one_off order type" do
    let(:order_type) { "one_off" }

    context "with valid add_ons using add_on_id" do
      let(:billing_items) { {"add_ons" => [{"add_on_id" => add_on.id, "name" => "My Add-on"}]} }

      it "returns success with normalized billing_items" do
        expect(result).to be_success
        expect(result.billing_items["add_ons"].first["id"]).to start_with("qta_")
      end
    end

    context "with valid add_ons without add_on_id" do
      let(:billing_items) { {"add_ons" => [{"name" => "Custom", "amount_cents" => 1000}]} }

      it "returns success" do
        expect(result).to be_success
      end
    end

    context "when add_on name is missing" do
      let(:billing_items) { {"add_ons" => [{"add_on_id" => add_on.id}]} }

      it "returns validation failure" do
        expect(result).not_to be_success
        expect(result.error.messages[:billing_items]).to include("add_ons[0].name is required")
      end
    end

    context "when add_on_id is absent and amount_cents is missing" do
      let(:billing_items) { {"add_ons" => [{"name" => "Custom"}]} }

      it "returns validation failure" do
        expect(result).not_to be_success
        expect(result.error.messages[:billing_items]).to include("add_ons[0].amount_cents is required when add_on_id is not provided")
      end
    end

    context "when add_on_id does not belong to organization" do
      let(:billing_items) { {"add_ons" => [{"add_on_id" => create(:add_on).id, "name" => "Test"}]} }

      it "returns validation failure" do
        expect(result).not_to be_success
        expect(result.error.messages[:billing_items]).to include("add_ons[0].add_on_id: add_on not found in organization")
      end
    end

    context "with plans (not allowed for one_off)" do
      let(:billing_items) { {"plans" => [{"plan_id" => plan.id}]} }

      it "returns validation failure" do
        expect(result).not_to be_success
        expect(result.error.messages[:billing_items]).to include("plans not allowed for one_off order type")
      end
    end
  end

  context "when billing_items is nil" do
    let(:order_type) { "subscription_creation" }
    let(:billing_items) { nil }

    it "returns success with empty normalized items" do
      expect(result).to be_success
    end
  end
end
