# frozen_string_literal: true

require "rails_helper"

RSpec.describe Subscriptions::ActivationRules::Payment::ValidateService do
  subject(:validate_service) { described_class.new(result, **args) }

  let(:result) { BaseService::Result.new }
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:subscription) { create(:subscription, customer:, plan:, organization:) }
  let(:rule) { {type: "payment", timeout_hours: 48} }
  let(:payment_method_params) { nil }

  let(:args) do
    {
      rule:,
      payment_method: payment_method_params,
      subscription:,
      customer:
    }
  end

  describe "#valid?" do
    context "with valid payment rule" do
      it "returns true" do
        expect(validate_service).to be_valid
      end
    end

    context "when timeout_hours is absent" do
      let(:rule) { {type: "payment"} }

      it "returns true" do
        expect(validate_service).to be_valid
      end
    end

    context "when timeout_hours is zero" do
      let(:rule) { {type: "payment", timeout_hours: 0} }

      it "returns true" do
        expect(validate_service).to be_valid
      end
    end

    context "when timeout_hours is negative" do
      let(:rule) { {type: "payment", timeout_hours: -1} }

      it "returns false" do
        expect(validate_service).not_to be_valid
      end
    end

    context "when timeout_hours is not an integer" do
      let(:rule) { {type: "payment", timeout_hours: "abc"} }

      it "returns false" do
        expect(validate_service).not_to be_valid
      end
    end

    context "when payment_method in params is manual" do
      let(:payment_method_params) { {payment_method_type: "manual"} }

      it "returns false" do
        expect(validate_service).not_to be_valid
      end
    end

    context "when payment_method in params is provider" do
      let(:payment_method_params) { {payment_method_type: "provider"} }

      it "returns true" do
        expect(validate_service).to be_valid
      end
    end

    context "when subscription has manual payment method type" do
      let(:subscription) { create(:subscription, customer:, plan:, organization:, payment_method_type: "manual") }

      it "returns false" do
        expect(validate_service).not_to be_valid
      end
    end

    context "when subscription is nil (creation flow)" do
      let(:subscription) { nil }

      context "when customer has a payment provider" do
        let(:customer) { create(:customer, organization:, payment_provider: "stripe") }

        it "returns true" do
          expect(validate_service).to be_valid
        end
      end

      context "when customer has no payment provider and no payment method in params" do
        let(:customer) { create(:customer, organization:, payment_provider: nil) }

        it "returns false" do
          expect(validate_service).not_to be_valid
        end
      end

      context "when customer has no payment provider but payment method params specify provider" do
        let(:customer) { create(:customer, organization:, payment_provider: nil) }
        let(:payment_method_params) { {payment_method_type: "provider"} }

        it "returns true" do
          expect(validate_service).to be_valid
        end
      end
    end
  end
end
