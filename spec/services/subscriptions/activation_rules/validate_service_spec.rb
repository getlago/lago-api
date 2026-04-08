# frozen_string_literal: true

require "rails_helper"

RSpec.describe Subscriptions::ActivationRules::ValidateService do
  subject(:validate_service) { described_class.new(result, **args) }

  let(:result) { BaseService::Result.new }
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:, payment_provider: "stripe") }
  let(:plan) { create(:plan, organization:) }
  let(:subscription) { nil }
  let(:subscription_type) { "create" }
  let(:activation_rules) { nil }
  let(:payment_method_params) { nil }

  let(:args) do
    {
      activation_rules:,
      subscription:,
      subscription_type:,
      payment_method: payment_method_params,
      customer:
    }
  end

  describe "#valid?" do

    context "when activation_rules is an empty array" do
      let(:activation_rules) { [] }

      it "returns true" do
        expect(validate_service).to be_valid
      end
    end

    context "when activation_rules is not an array" do
      let(:activation_rules) { "invalid" }

      it "returns false" do
        expect(validate_service).not_to be_valid
      end
    end

    context "when activation_rules is a hash" do
      let(:activation_rules) { {type: "payment"} }

      it "returns false" do
        expect(validate_service).not_to be_valid
      end
    end

    context "with valid payment rule" do
      let(:activation_rules) { [{type: "payment", timeout_hours: 48}] }

      it "returns true" do
        expect(validate_service).to be_valid
      end
    end

    context "with unknown rule type" do
      let(:activation_rules) { [{type: "unknown"}] }

      it "returns false" do
        expect(validate_service).not_to be_valid
      end
    end

    context "with multiple rules including unknown type" do
      let(:activation_rules) { [{type: "payment", timeout_hours: 48}, {type: "unknown"}] }

      it "returns false" do
        expect(validate_service).not_to be_valid
      end
    end

    context "when subscription_type is update" do
      let(:subscription_type) { "update" }

      context "when subscription is pending" do
        let(:subscription) { create(:subscription, :pending, customer:, plan:, organization:) }
        let(:activation_rules) { [{type: "payment"}] }

        it "returns true" do
          expect(validate_service).to be_valid
        end
      end

      context "when subscription is active" do
        let(:subscription) { create(:subscription, customer:, plan:, organization:) }
        let(:activation_rules) { [{type: "payment"}] }

        it "returns false" do
          expect(validate_service).not_to be_valid
        end
      end

      context "when subscription is incomplete" do
        let(:subscription) { create(:subscription, :incomplete, customer:, plan:, organization:) }
        let(:activation_rules) { [{type: "payment"}] }

        it "returns false" do
          expect(validate_service).not_to be_valid
        end
      end
    end

    context "when subscription is nil" do
      let(:activation_rules) { [{type: "payment", timeout_hours: 24}] }

      it "returns true" do
        expect(validate_service).to be_valid
      end
    end

    context "with invalid timeout_hours via delegation" do
      let(:activation_rules) { [{type: "payment", timeout_hours: -5}] }

      it "returns false" do
        expect(validate_service).not_to be_valid
      end
    end

    context "with manual payment method via delegation" do
      let(:activation_rules) { [{type: "payment", timeout_hours: 48}] }
      let(:payment_method_params) { {payment_method_type: "manual"} }

      it "returns false" do
        expect(validate_service).not_to be_valid
      end
    end
  end
end
