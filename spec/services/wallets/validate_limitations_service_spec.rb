# frozen_string_literal: true

require "rails_helper"

RSpec.describe Wallets::ValidateLimitationsService, type: :service do
  subject(:validate_service) { described_class.new(result, **args) }

  let(:result) { BaseService::Result.new }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:args) do
    {
      applies_to: limitations
    }
  end

  describe ".valid?" do
    context "when there is no applies_to attribute" do
      let(:args) do
        {}
      end

      it "returns true" do
        expect(validate_service).to be_valid
      end
    end

    context "when there is wrong fee type" do
      let(:limitations) do
        {
          fee_types: %w[invalid_fee_type charge]
        }
      end

      it "returns false and result has errors" do
        expect(validate_service).not_to be_valid
        expect(result.error.messages[:allowed_fee_types]).to eq(["invalid_fee_types"])
      end
    end

    context "when limitations are valid" do
      let(:limitations) do
        {
          fee_types: %w[charge subscription]
        }
      end

      it "returns true and result has no errors" do
        expect(validate_service).to be_valid
        expect(result.error).to be_nil
      end
    end
  end
end
