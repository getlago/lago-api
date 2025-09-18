# frozen_string_literal: true

require "rails_helper"

RSpec.describe WalletTransactions::ValidateService do
  subject(:validate_service) { described_class.new(result, **args) }

  let(:result) { BaseService::Result.new }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, customer:) }
  let(:wallet) { create(:wallet, customer:) }
  let(:wallet_id) { wallet.id }
  let(:paid_credits) { "1.00" }
  let(:granted_credits) { "0.00" }
  let(:voided_credits) { "0.00" }
  let(:args) do
    {
      wallet_id:,
      customer_id: customer.external_id,
      organization_id: organization.id,
      paid_credits:,
      granted_credits:,
      voided_credits:,
      **((name == :undefined) ? {} : {name:})
    }
  end
  let(:name) { :undefined }

  before { subscription }

  describe ".valid?" do
    it "returns true" do
      expect(validate_service).to be_valid
    end

    context "when wallet does not exists" do
      let(:wallet_id) { "123456" }

      it "returns false and result has errors" do
        expect(validate_service).not_to be_valid
        expect(result.error.messages[:wallet_id]).to eq(["wallet_not_found"])
      end
    end

    context "with invalid paid_credits" do
      let(:paid_credits) { "foobar" }

      it "returns false and result has errors" do
        expect(validate_service).not_to be_valid
        expect(result.error.messages[:paid_credits]).to eq(["invalid_paid_credits", "invalid_amount"])
      end
    end

    context "with invalid granted_credits" do
      let(:granted_credits) { "foobar" }

      it "returns false and result has errors" do
        expect(validate_service).not_to be_valid
        expect(result.error.messages[:granted_credits]).to eq(["invalid_granted_credits", "invalid_amount"])
      end
    end

    context "with invalid voided_credits" do
      let(:voided_credits) { "foobar" }

      it "returns false and result has errors" do
        expect(validate_service).not_to be_valid
        expect(result.error.messages[:voided_credits]).to eq(["invalid_voided_credits", "invalid_amount"])
      end
    end

    context "with valid voided_credits but insufficient credits" do
      let(:voided_credits) { "1.00" }

      it "returns false and result has errors" do
        expect(validate_service).not_to be_valid
        expect(result.error.messages[:voided_credits]).to eq(["insufficient_credits"])
      end
    end

    context "with invalid metadata" do
      let(:args) do
        {
          wallet_id:,
          customer_id: customer.external_id,
          organization_id: organization.id,
          paid_credits:,
          granted_credits:,
          voided_credits:,
          metadata: [{"key" => "key", "value" => {"key" => "nested_value"}}]
        }
      end

      it "returns false and result has errors for metadata" do
        expect(validate_service).not_to be_valid
        expect(result.error.messages[:metadata]).to eq(["nested_structure_not_allowed"])
      end
    end

    context "with valid name" do
      let(:name) { "Valid Transaction Name" }

      it { is_expected.to be_valid }
    end

    context "with blank name" do
      let(:name) { "" }

      it { is_expected.to be_valid }
    end

    context "with nil name" do
      let(:name) { nil }

      it { is_expected.to be_valid }
    end

    context "with name at maximum length" do
      let(:name) { "a" * 255 }

      it { is_expected.to be_valid }
    end

    context "with name that is too long" do
      let(:name) { "a" * 256 }

      it "returns false and result has errors" do
        expect(validate_service).not_to be_valid
        expect(result.error.messages[:name]).to eq(["too_long"])
      end
    end

    context "with name that is not a string" do
      let(:name) { 123 }

      it "returns false and result has errors" do
        expect(validate_service).not_to be_valid
        expect(result.error.messages[:name]).to eq(["invalid_value"])
      end
    end
  end
end
