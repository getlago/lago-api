# frozen_string_literal: true

require "rails_helper"

RSpec.describe Quotes::BillingItemsValidator do
  subject(:validator) { described_class.new(result, billing_items:, order_type:) }

  let(:result) { BaseService::Result.new }
  let(:order_type) { "subscription_creation" }
  let(:billing_items) do
    {
      "plan" => {
        "id" => SecureRandom.uuid,
        "position" => 1,
        "plan_code" => "enterprise",
        "plan_id" => SecureRandom.uuid,
        "plan_name" => "Enterprise Plan"
      },
      "coupons" => [],
      "wallet_credits" => []
    }
  end

  describe "#valid?" do
    it "returns true for valid subscription_creation billing items" do
      expect(validator).to be_valid
    end

    context "with valid one_off billing items" do
      let(:order_type) { "one_off" }
      let(:billing_items) do
        {
          "add_ons" => [
            {
              "id" => SecureRandom.uuid,
              "position" => 1,
              "add_on_code" => "setup",
              "add_on_id" => SecureRandom.uuid,
              "name" => "Setup fee",
              "units" => 1,
              "amount_cents" => 10_000,
              "total_amount_cents" => 10_000
            }
          ]
        }
      end

      it "returns true" do
        expect(validator).to be_valid
      end
    end

    context "when billing_items is not a hash" do
      let(:billing_items) { "invalid" }

      it "returns false with invalid_format error" do
        expect(validator).not_to be_valid
        expect(result.error.messages[:billing_items]).to include("invalid_format")
      end
    end

    context "when billing_items is an array" do
      let(:billing_items) { [] }

      it "returns false with invalid_format error" do
        expect(validator).not_to be_valid
        expect(result.error.messages[:billing_items]).to include("invalid_format")
      end
    end

    context "when add_ons present on subscription_creation" do
      let(:billing_items) do
        {
          "plan" => {},
          "add_ons" => [{"id" => SecureRandom.uuid, "position" => 1, "name" => "Setup", "add_on_id" => SecureRandom.uuid}]
        }
      end

      it "returns false with add_ons_not_allowed error" do
        expect(validator).not_to be_valid
        expect(result.error.messages[:billing_items]).to include("add_ons_not_allowed_for_subscription")
      end
    end

    context "when add_ons present on subscription_amendment" do
      let(:order_type) { "subscription_amendment" }
      let(:billing_items) do
        {
          "plan" => {},
          "add_ons" => [{"id" => SecureRandom.uuid, "position" => 1, "name" => "Setup", "add_on_id" => SecureRandom.uuid}]
        }
      end

      it "returns false with add_ons_not_allowed error" do
        expect(validator).not_to be_valid
        expect(result.error.messages[:billing_items]).to include("add_ons_not_allowed_for_subscription")
      end
    end

    context "when plan present on one_off" do
      let(:order_type) { "one_off" }
      let(:billing_items) do
        {
          "plan" => {"id" => SecureRandom.uuid, "position" => 1, "plan_id" => SecureRandom.uuid, "plan_name" => "Plan"},
          "add_ons" => []
        }
      end

      it "returns false with plan_not_allowed error" do
        expect(validator).not_to be_valid
        expect(result.error.messages[:billing_items]).to include("plan_not_allowed_for_one_off")
      end
    end

    context "when coupons present on one_off" do
      let(:order_type) { "one_off" }
      let(:billing_items) do
        {
          "add_ons" => [],
          "coupons" => [{"id" => SecureRandom.uuid, "position" => 1, "coupon_id" => SecureRandom.uuid}]
        }
      end

      it "returns false with coupons_not_allowed error" do
        expect(validator).not_to be_valid
        expect(result.error.messages[:billing_items]).to include("coupons_not_allowed_for_one_off")
      end
    end

    context "when wallet_credits present on one_off" do
      let(:order_type) { "one_off" }
      let(:billing_items) do
        {
          "add_ons" => [],
          "wallet_credits" => [{"id" => SecureRandom.uuid, "position" => 1}]
        }
      end

      it "returns false with wallet_credits_not_allowed error" do
        expect(validator).not_to be_valid
        expect(result.error.messages[:billing_items]).to include("wallet_credits_not_allowed_for_one_off")
      end
    end

    context "when duplicate add_on_ids exist" do
      let(:order_type) { "one_off" }
      let(:duplicate_add_on_id) { SecureRandom.uuid }
      let(:billing_items) do
        {
          "add_ons" => [
            {"id" => SecureRandom.uuid, "position" => 1, "add_on_id" => duplicate_add_on_id, "name" => "Add-on A", "amount_cents" => 100},
            {"id" => SecureRandom.uuid, "position" => 2, "add_on_id" => duplicate_add_on_id, "name" => "Add-on B", "amount_cents" => 200}
          ]
        }
      end

      it "returns false with duplicate_add_on error" do
        expect(validator).not_to be_valid
        expect(result.error.messages[:billing_items]).to include("duplicate_add_on")
      end
    end

    context "when multiple add_ons have nil add_on_id (custom line items)" do
      let(:order_type) { "one_off" }
      let(:billing_items) do
        {
          "add_ons" => [
            {"id" => SecureRandom.uuid, "position" => 1, "add_on_id" => nil, "name" => "Custom A", "amount_cents" => 100},
            {"id" => SecureRandom.uuid, "position" => 2, "add_on_id" => nil, "name" => "Custom B", "amount_cents" => 200}
          ]
        }
      end

      it "returns true because nil add_on_ids are excluded from duplicate check" do
        expect(validator).to be_valid
      end
    end

    context "when duplicate coupon_ids exist" do
      let(:duplicate_coupon_id) { SecureRandom.uuid }
      let(:billing_items) do
        {
          "plan" => {"id" => SecureRandom.uuid, "position" => 1, "plan_id" => SecureRandom.uuid, "plan_name" => "Plan"},
          "coupons" => [
            {"id" => SecureRandom.uuid, "position" => 1, "coupon_id" => duplicate_coupon_id},
            {"id" => SecureRandom.uuid, "position" => 2, "coupon_id" => duplicate_coupon_id}
          ],
          "wallet_credits" => []
        }
      end

      it "returns false with duplicate_coupon error" do
        expect(validator).not_to be_valid
        expect(result.error.messages[:billing_items]).to include("duplicate_coupon")
      end
    end

    context "when subscription_external_id missing on amendment plan" do
      let(:order_type) { "subscription_amendment" }
      let(:billing_items) do
        {
          "plan" => {"id" => SecureRandom.uuid, "position" => 1, "plan_id" => SecureRandom.uuid, "plan_name" => "Plan"},
          "coupons" => [],
          "wallet_credits" => []
        }
      end

      it "returns false with missing_subscription_external_id error" do
        expect(validator).not_to be_valid
        expect(result.error.messages[:billing_items]).to include("missing_subscription_external_id")
      end
    end

    context "when subscription_external_id present on amendment plan" do
      let(:order_type) { "subscription_amendment" }
      let(:billing_items) do
        {
          "plan" => {
            "id" => SecureRandom.uuid,
            "position" => 1,
            "plan_id" => SecureRandom.uuid,
            "plan_name" => "Plan",
            "subscription_external_id" => "sub_ext_001"
          },
          "coupons" => [],
          "wallet_credits" => []
        }
      end

      it "returns true" do
        expect(validator).to be_valid
      end
    end

    context "when subscription_external_id not required for subscription_creation" do
      let(:order_type) { "subscription_creation" }
      let(:billing_items) do
        {
          "plan" => {"id" => SecureRandom.uuid, "position" => 1, "plan_id" => SecureRandom.uuid, "plan_name" => "Plan"},
          "coupons" => [],
          "wallet_credits" => []
        }
      end

      it "returns true" do
        expect(validator).to be_valid
      end
    end

    context "when duplicate positions in add_ons" do
      let(:order_type) { "one_off" }
      let(:billing_items) do
        {
          "add_ons" => [
            {"id" => SecureRandom.uuid, "position" => 1, "add_on_id" => SecureRandom.uuid, "name" => "A", "amount_cents" => 100},
            {"id" => SecureRandom.uuid, "position" => 1, "add_on_id" => SecureRandom.uuid, "name" => "B", "amount_cents" => 200}
          ]
        }
      end

      it "returns false with duplicate_position error" do
        expect(validator).not_to be_valid
        expect(result.error.messages[:billing_items]).to include("duplicate_position_in_add_ons")
      end
    end

    context "when add_on entry missing name" do
      let(:order_type) { "one_off" }
      let(:billing_items) do
        {
          "add_ons" => [
            {"id" => SecureRandom.uuid, "position" => 1, "add_on_id" => SecureRandom.uuid, "amount_cents" => 100}
          ]
        }
      end

      it "returns false with add_on_missing_name error" do
        expect(validator).not_to be_valid
        expect(result.error.messages[:billing_items]).to include("add_on_missing_name")
      end
    end

    context "when custom add_on (no add_on_id) missing amount_cents" do
      let(:order_type) { "one_off" }
      let(:billing_items) do
        {
          "add_ons" => [
            {"id" => SecureRandom.uuid, "position" => 1, "add_on_id" => nil, "add_on_code" => nil, "name" => "Custom item"}
          ]
        }
      end

      it "returns false with custom_add_on_missing_amount error" do
        expect(validator).not_to be_valid
        expect(result.error.messages[:billing_items]).to include("custom_add_on_missing_amount")
      end
    end

    context "when custom add_on has amount_cents" do
      let(:order_type) { "one_off" }
      let(:billing_items) do
        {
          "add_ons" => [
            {"id" => SecureRandom.uuid, "position" => 1, "add_on_id" => nil, "add_on_code" => nil, "name" => "Custom item", "amount_cents" => 500}
          ]
        }
      end

      it "returns true" do
        expect(validator).to be_valid
      end
    end
  end
end
