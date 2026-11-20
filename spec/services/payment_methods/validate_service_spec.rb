# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentMethods::ValidateService do
  subject(:validate_service) { described_class.new(result, **args) }

  let(:result) { BaseResult[:payment_method].new }
  let(:payment_method) { create(:payment_method, organization:) }
  let(:payment_method_params) do
    {
      payment_method_id: payment_method.id,
      payment_method_type: "provider"
    }
  end
  let(:args) do
    {
      payment_method: payment_method_params
    }
  end

  let_it_be(:organization) { create_default(:organization) }
  let_it_be(:membership) { create(:membership) }

  before_all do
    create_default(:customer)
  end

  describe ".valid?" do
    context "when there is no payment_method attribute" do
      let(:args) do
        {}
      end

      it "returns true" do
        expect(validate_service).to be_valid
      end
    end

    context "when provider payment method is valid" do
      before do
        result.payment_method = payment_method
      end

      it "returns true and result has no errors" do
        expect(validate_service).to be_valid
        expect(result.error).to be_nil
      end
    end

    context "when the payment method is a shared payment token row" do
      let(:payment_method) { create(:payment_method, organization:, provider_method_type: "shared_payment_token", provider_method_id: "spt_abc_123") }

      before do
        result.payment_method = payment_method
      end

      it "returns false and result has errors" do
        expect(validate_service).not_to be_valid
        expect(result.error.messages[:payment_method]).to eq(["invalid_payment_method"])
      end

      context "when the caller allows it" do
        let(:args) { {payment_method: payment_method_params, allow_shared_payment_token: true} }

        it "returns true and result has no errors" do
          expect(validate_service).to be_valid
          expect(result.error).to be_nil
        end
      end
    end

    context "when manual payment method is valid" do
      let(:payment_method_params) do
        {
          payment_method_type: "manual"
        }
      end

      it "returns true and result has no errors" do
        expect(validate_service).to be_valid
        expect(result.error).to be_nil
      end
    end

    context "with invalid payment method type" do
      let(:payment_method_params) do
        {
          payment_method_id: payment_method.id,
          payment_method_type: "invalid"
        }
      end

      it "returns false and result has errors" do
        expect(validate_service).not_to be_valid
        expect(result.error.messages[:payment_method]).to eq(["invalid_payment_method"])
      end
    end

    context "with invalid payment method reference" do
      let(:payment_method_params) do
        {
          payment_method_id: "invalid",
          payment_method_type: "provider"
        }
      end

      it "returns false and result has errors" do
        expect(validate_service).not_to be_valid
        expect(result.error.messages[:payment_method]).to eq(["invalid_payment_method"])
      end
    end
  end
end
