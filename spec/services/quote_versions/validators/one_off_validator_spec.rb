# frozen_string_literal: true

require "rails_helper"

RSpec.describe QuoteVersions::Validators::OneOffValidator do
  subject(:validator) { described_class.new(result, quote_version:, scope:) }

  let(:result) { BaseService::Result.new }
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:quote) { create(:quote, organization:, customer:, order_type: :one_off) }
  let(:quote_version) { create(:quote_version, quote:, organization:, currency: "EUR", billing_items:) }
  let(:add_on) { create(:add_on, organization:) }
  let(:scope) { :approve }
  let(:add_on_item) do
    {
      "id" => add_on.id,
      "localId" => "3d08b2df-4e4c-4d58-b415-a525c1663735",
      "type" => "add_on",
      "payload" => payload
    }
  end
  let(:payload) do
    {
      "code" => add_on.code,
      "units" => 1,
      "unitAmountCents" => 10_000,
      "totalAmountCents" => 10_000
    }
  end
  let(:billing_items) { {"addOns" => [add_on_item]} }

  describe "#valid?" do
    context "with a complete valid quote version" do
      it "is valid and leaves the result untouched" do
        expect(validator).to be_valid
        expect(result).to be_success
      end
    end

    context "with both structural and business errors" do
      let(:payload) { super().merge("units" => 0) }
      let(:quote_version) { create(:quote_version, quote:, organization:, currency: "DOUBLOON", billing_items:) }

      it "returns the structural errors first" do
        expect(validator).not_to be_valid
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages).to eq({"billing_items.addOns.0.payload.units": ["invalid_value"]})
      end
    end

    context "with a valid structure and an unknown add-on" do
      let(:add_on_item) { super().merge("id" => "11111111-2222-3333-4444-555555555555") }

      it "reports the business error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.addOns.0.id": ["add_on_not_found"]})
      end
    end

    context "when the structure is invalid" do
      let(:add_on_item) { super().merge("taxCodes" => ["vat_20"], "id" => "11111111-2222-3333-4444-555555555555") }
      let(:quote_version) { create(:quote_version, quote:, organization:, currency: nil, billing_items:) }

      it "returns only structural errors and skips business validation" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq(
          {"billing_items.addOns.0.taxCodes": ["unsupported_key"]}
        )
      end
    end

    context "when billing_items has symbol keys" do
      let(:billing_items) do
        {
          addOns: [
            {
              id: add_on.id,
              localId: "3d08b2df-4e4c-4d58-b415-a525c1663735",
              type: "add_on",
              payload: {code: add_on.code, units: 1, unitAmountCents: 10_000, totalAmountCents: 10_000}
            }
          ]
        }
      end

      it "normalizes them before validating" do
        expect(validator).to be_valid
      end
    end

    context "when billing_items is nil at update scope" do
      let(:scope) { :update }
      let(:billing_items) { nil }

      it "is valid" do
        expect(validator).to be_valid
        expect(result).to be_success
      end
    end
  end
end
