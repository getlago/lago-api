# frozen_string_literal: true

require "rails_helper"

RSpec.describe Quotes::BillingItems::ValidateService do
  subject(:service) { described_class.new(organization:, order_type:, billing_items:) }

  let(:organization) { create(:organization) }
  let(:plan) { create(:plan, organization:) }
  let(:coupon) { create(:coupon, organization:) }
  let(:add_on) { create(:add_on, organization:) }

  describe "#call" do
    let(:result) { service.call }

    context "with subscription_creation order type" do
      let(:order_type) { "subscription_creation" }

      context "with valid plans" do
        let(:billing_items) do
          {
            "plans" => [{"plan_id" => plan.id, "plan_name" => "Enterprise", "position" => 1}],
            "coupons" => [],
            "wallet_credits" => []
          }
        end

        it "returns success with billing_items" do
          expect(result).to be_success
          expect(result.billing_items["plans"].first["plan_id"]).to eq(plan.id)
        end

        it "generates ids for items missing them" do
          expect(result.billing_items["plans"].first["id"]).to start_with("qtp_")
        end

        it "preserves existing ids" do
          billing_items["plans"].first["id"] = "qtp_existing"
          expect(result.billing_items["plans"].first["id"]).to eq("qtp_existing")
        end
      end

      context "with valid coupons" do
        let(:billing_items) do
          {
            "plans" => [{"plan_id" => plan.id, "plan_name" => "Enterprise", "position" => 1}],
            "coupons" => [{"coupon_id" => coupon.id, "coupon_type" => "fixed_amount", "amount_cents" => 5000, "position" => 1}],
            "wallet_credits" => []
          }
        end

        it "returns success and generates coupon id" do
          expect(result).to be_success
          expect(result.billing_items["coupons"].first["id"]).to start_with("qtc_")
        end
      end

      context "with valid wallet_credits" do
        let(:billing_items) do
          {
            "plans" => [{"plan_id" => plan.id, "plan_name" => "Enterprise", "position" => 1}],
            "wallet_credits" => [
              {
                "name" => "Credits",
                "currency" => "EUR",
                "rate_amount" => "1.0",
                "paid_credits" => "500.0",
                "granted_credits" => "500.0",
                "position" => 1,
                "recurring_transaction_rules" => [
                  {"trigger" => "interval", "interval" => "monthly", "paid_credits" => "500.0", "granted_credits" => "500.0"}
                ]
              }
            ]
          }
        end

        it "generates ids for wallet credit and its recurring rules" do
          expect(result).to be_success
          credit = result.billing_items["wallet_credits"].first
          expect(credit["id"]).to start_with("qtw_")
          expect(credit["recurring_transaction_rules"].first["id"]).to start_with("qtrr_")
        end
      end

      context "when add_ons are present" do
        let(:billing_items) do
          {"add_ons" => [{"name" => "X", "amount_cents" => 100, "position" => 1}]}
        end

        it "returns validation error" do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:billing_items]).to include("add_ons not allowed for subscription order type")
        end
      end

      context "when plan_id is missing" do
        let(:billing_items) do
          {"plans" => [{"plan_name" => "Enterprise", "position" => 1}]}
        end

        it "returns validation error" do
          expect(result).not_to be_success
          expect(result.error.messages[:billing_items]).to include("plans[0].plan_id is required")
        end
      end

      context "when plan does not belong to organization" do
        let(:other_plan) { create(:plan) }
        let(:billing_items) do
          {"plans" => [{"plan_id" => other_plan.id, "plan_name" => "X", "position" => 1}]}
        end

        it "returns validation error" do
          expect(result).not_to be_success
          expect(result.error.messages[:billing_items]).to include("plans[0].plan_id: plan not found in organization")
        end
      end

      context "when coupon_type is invalid" do
        let(:billing_items) do
          {"coupons" => [{"coupon_id" => coupon.id, "coupon_type" => "unknown", "position" => 1}]}
        end

        it "returns validation error" do
          expect(result).not_to be_success
          expect(result.error.messages[:billing_items]).to include("coupons[0].coupon_type is invalid")
        end
      end

      context "when coupon does not belong to organization" do
        let(:other_coupon) { create(:coupon) }
        let(:billing_items) do
          {"coupons" => [{"coupon_id" => other_coupon.id, "coupon_type" => "fixed_amount", "position" => 1}]}
        end

        it "returns validation error" do
          expect(result).not_to be_success
          expect(result.error.messages[:billing_items]).to include("coupons[0].coupon_id: coupon not found in organization")
        end
      end
    end

    context "with one_off order type" do
      let(:order_type) { "one_off" }

      context "with valid add_ons using catalog reference" do
        let(:billing_items) do
          {"add_ons" => [{"add_on_id" => add_on.id, "name" => "Implementation", "amount_cents" => 100_000, "position" => 1}]}
        end

        it "returns success and generates id" do
          expect(result).to be_success
          expect(result.billing_items["add_ons"].first["id"]).to start_with("qta_")
        end
      end

      context "with custom add_on (no catalog reference)" do
        let(:billing_items) do
          {"add_ons" => [{"name" => "Custom Work", "amount_cents" => 50_000, "position" => 1}]}
        end

        it "returns success" do
          expect(result).to be_success
          expect(result.billing_items["add_ons"].first["id"]).to start_with("qta_")
        end
      end

      context "when add_on_id does not belong to organization" do
        let(:other_add_on) { create(:add_on) }
        let(:billing_items) do
          {"add_ons" => [{"add_on_id" => other_add_on.id, "name" => "X", "amount_cents" => 1, "position" => 1}]}
        end

        it "returns validation error" do
          expect(result).not_to be_success
          expect(result.error.messages[:billing_items]).to include("add_ons[0].add_on_id: add_on not found in organization")
        end
      end

      context "when no add_on_id and amount_cents is missing" do
        let(:billing_items) do
          {"add_ons" => [{"name" => "Custom", "position" => 1}]}
        end

        it "returns validation error" do
          expect(result).not_to be_success
          expect(result.error.messages[:billing_items]).to include("add_ons[0].amount_cents is required when add_on_id is not provided")
        end
      end

      context "when add_on name is missing" do
        let(:billing_items) do
          {"add_ons" => [{"amount_cents" => 1000, "position" => 1}]}
        end

        it "returns validation error" do
          expect(result).not_to be_success
          expect(result.error.messages[:billing_items]).to include("add_ons[0].name is required")
        end
      end

      context "when plans are present" do
        let(:billing_items) do
          {"plans" => [{"plan_id" => plan.id, "plan_name" => "X", "position" => 1}]}
        end

        it "returns validation error" do
          expect(result).not_to be_success
          expect(result.error.messages[:billing_items]).to include("plans not allowed for one_off order type")
        end
      end
    end

    context "with empty billing_items" do
      let(:order_type) { "subscription_creation" }
      let(:billing_items) { {} }

      it "returns success with normalized empty structure" do
        expect(result).to be_success
        expect(result.billing_items["plans"]).to eq([])
        expect(result.billing_items["coupons"]).to eq([])
        expect(result.billing_items["wallet_credits"]).to eq([])
      end
    end

    context "with nil billing_items" do
      let(:order_type) { "one_off" }
      let(:billing_items) { nil }

      it "returns success" do
        expect(result).to be_success
        expect(result.billing_items["add_ons"]).to eq([])
      end
    end

    context "with multiple errors" do
      let(:order_type) { "subscription_creation" }
      let(:billing_items) do
        {
          "plans" => [
            {"plan_name" => "Missing ID"},
            {"plan_id" => "non-existent-uuid", "plan_name" => "Bad ID"}
          ]
        }
      end

      it "returns all errors at once" do
        expect(result).not_to be_success
        errors = result.error.messages[:billing_items]
        expect(errors).to include("plans[0].plan_id is required")
        expect(errors).to include("plans[1].plan_id: plan not found in organization")
      end
    end
  end
end
