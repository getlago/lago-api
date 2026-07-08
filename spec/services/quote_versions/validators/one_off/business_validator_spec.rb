# frozen_string_literal: true

require "rails_helper"

RSpec.describe QuoteVersions::Validators::OneOff::BusinessValidator do
  subject(:validator) { described_class.new(result, quote_version:, billing_items:, scope:) }

  let(:result) { BaseService::Result.new }
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:quote) { create(:quote, organization:, customer:, order_type: :one_off) }
  let(:quote_version) { create(:quote_version, quote:, organization:, currency: "EUR") }
  let(:add_on) { create(:add_on, organization:) }
  let(:scope) { :update }
  let(:add_on_item) do
    {
      "id" => add_on.id,
      "localId" => "3d08b2df-4e4c-4d58-b415-a525c1663735",
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
    context "with a valid quote version" do
      it "is valid for both scopes" do
        expect(described_class.new(BaseService::Result.new, quote_version:, billing_items:, scope: :update)).to be_valid
        expect(described_class.new(BaseService::Result.new, quote_version:, billing_items:, scope: :approve)).to be_valid
      end
    end

    context "when the currency is missing" do
      let(:quote_version) { create(:quote_version, quote:, organization:, currency: nil) }

      it "is valid at update scope" do
        expect(validator).to be_valid
      end

      context "when the scope is approve" do
        let(:scope) { :approve }

        it "requires the currency" do
          expect(validator).not_to be_valid
          expect(result.error.messages).to eq({currency: ["value_is_mandatory"]})
        end
      end
    end

    context "when the currency is not ISO 4217" do
      let(:quote_version) { create(:quote_version, quote:, organization:, currency: "DOUBLOON") }

      it "returns an invalid_currency error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({currency: ["invalid_currency"]})
      end
    end

    context "when the add-on does not exist" do
      let(:add_on_item) { super().merge("id" => "11111111-2222-3333-4444-555555555555") }

      it "returns an add_on_not_found error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.addOns.0.id": ["add_on_not_found"]})
      end
    end

    context "when the add-on is discarded" do
      before { add_on.discard! }

      it "is valid" do
        expect(validator).to be_valid
      end
    end

    context "when the add-on belongs to another organization" do
      let(:add_on) { create(:add_on) }

      it "returns an add_on_not_found error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.addOns.0.id": ["add_on_not_found"]})
      end
    end

    context "when only fromDatetime is present" do
      let(:payload) { super().merge("fromDatetime" => "2026-01-01T00:00:00Z", "toDatetime" => nil) }

      it "requires toDatetime" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.addOns.0.payload.toDatetime": ["value_is_mandatory"]})
      end
    end

    context "when only toDatetime is present" do
      let(:payload) { super().merge("fromDatetime" => nil, "toDatetime" => "2026-02-01T00:00:00Z") }

      it "requires fromDatetime" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.addOns.0.payload.fromDatetime": ["value_is_mandatory"]})
      end
    end

    context "when fromDatetime is after toDatetime" do
      let(:payload) { super().merge("fromDatetime" => "2026-02-01T00:00:00Z", "toDatetime" => "2026-01-01T00:00:00Z") }

      it "returns an invalid_date_range error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.addOns.0.payload.fromDatetime": ["invalid_date_range"]})
      end
    end

    context "when fromDatetime equals toDatetime" do
      let(:payload) { super().merge("fromDatetime" => "2026-01-01T00:00:00Z", "toDatetime" => "2026-01-01T00:00:00Z") }

      it "is valid" do
        expect(validator).to be_valid
      end
    end

    context "when only overrides fromDatetime is present" do
      let(:add_on_item) { super().merge("overrides" => {"fromDatetime" => "2026-01-01T00:00:00Z"}) }

      it "requires overrides toDatetime" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.addOns.0.overrides.toDatetime": ["value_is_mandatory"]})
      end
    end

    context "when only overrides toDatetime is present" do
      let(:add_on_item) { super().merge("overrides" => {"toDatetime" => "2026-02-01T00:00:00Z"}) }

      it "requires overrides fromDatetime" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.addOns.0.overrides.fromDatetime": ["value_is_mandatory"]})
      end
    end

    context "when overrides fromDatetime is after toDatetime" do
      let(:add_on_item) do
        super().merge("overrides" => {"fromDatetime" => "2026-02-01T00:00:00Z", "toDatetime" => "2026-01-01T00:00:00Z"})
      end

      it "returns an invalid_date_range error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.addOns.0.overrides.fromDatetime": ["invalid_date_range"]})
      end
    end

    context "when overrides fromDatetime equals toDatetime" do
      let(:add_on_item) do
        super().merge("overrides" => {"fromDatetime" => "2026-01-01T00:00:00Z", "toDatetime" => "2026-01-01T00:00:00Z"})
      end

      it "is valid" do
        expect(validator).to be_valid
      end
    end

    context "with errors on multiple add_ons" do
      let(:billing_items) do
        {
          "addOns" => [
            add_on_item,
            add_on_item.merge("id" => "11111111-2222-3333-4444-555555555555")
          ]
        }
      end

      it "keys each error with the add_on index" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.addOns.1.id": ["add_on_not_found"]})
      end
    end
  end
end
