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
      it { is_expected.to be_valid }
    end

    context "when timeout_hours is absent" do
      let(:rule) { {type: "payment"} }

      it { is_expected.to be_valid }
    end

    context "when timeout_hours is zero" do
      let(:rule) { {type: "payment", timeout_hours: 0} }

      it { is_expected.to be_valid }
    end

    context "when timeout_hours is negative" do
      let(:rule) { {type: "payment", timeout_hours: -1} }

      it "is invalid with value_must_be_positive_or_zero error" do
        expect(validate_service).not_to be_valid
        expect(result.error.messages[:timeout_hours]).to eq(["value_must_be_positive_or_zero"])
      end
    end

    context "when timeout_hours is not an integer" do
      let(:rule) { {type: "payment", timeout_hours: "abc"} }

      it "is invalid with value_must_be_positive_or_zero error" do
        expect(validate_service).not_to be_valid
        expect(result.error.messages[:timeout_hours]).to eq(["value_must_be_positive_or_zero"])
      end
    end

    context "when payment_method params are present" do
      context "when payment_method_type is manual" do
        let(:payment_method_params) { {payment_method_type: "manual"} }

        it "is invalid with invalid_for_payment_activation_rules error" do
          expect(validate_service).not_to be_valid
          expect(result.error.messages[:payment_method]).to eq(["invalid_for_payment_activation_rules"])
        end
      end

      context "when payment_method_type is provider" do
        let(:payment_method_params) { {payment_method_type: "provider"} }

        it { is_expected.to be_valid }
      end
    end

    context "when payment_method params are absent" do
      context "when subscription exists" do
        context "when subscription payment_method_type is manual" do
          let(:subscription) { create(:subscription, customer:, plan:, organization:, payment_method_type: "manual") }

          it "is invalid with invalid_for_payment_activation_rules error" do
            expect(validate_service).not_to be_valid
            expect(result.error.messages[:payment_method]).to eq(["invalid_for_payment_activation_rules"])
          end
        end

        context "when subscription payment_method_type is provider" do
          let(:subscription) { create(:subscription, customer:, plan:, organization:, payment_method_type: "provider") }

          it { is_expected.to be_valid }
        end
      end

      context "when subscription is nil" do
        let(:subscription) { nil }

        context "when customer has a payment provider" do
          let(:customer) { create(:customer, organization:, payment_provider: "stripe") }

          it { is_expected.to be_valid }
        end

        context "when customer has no payment provider" do
          let(:customer) { create(:customer, organization:, payment_provider: nil) }

          it "is invalid with no_linked_payment_provider error" do
            expect(validate_service).not_to be_valid
            expect(result.error.messages[:payment_method]).to eq(["no_linked_payment_provider"])
          end
        end
      end
    end
  end
end
