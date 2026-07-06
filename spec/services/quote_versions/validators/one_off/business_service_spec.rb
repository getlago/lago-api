# frozen_string_literal: true

require "rails_helper"

RSpec.describe QuoteVersions::Validators::OneOff::BusinessService do
  subject(:validator) { described_class.new(quote_version:, billing_items:, scope:, payload_valid:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:quote) { create(:quote, organization:, customer:, order_type: :one_off) }
  let(:quote_version) { create(:quote_version, quote:, organization:, currency: "EUR") }
  let(:add_on) { create(:add_on, organization:) }
  let(:scope) { :update }
  let(:payload_valid) { true }
  let(:addon_item) do
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
      "unit_amount_cents" => 10_000,
      "total_amount_cents" => 10_000
    }
  end
  let(:billing_items) { {"addons" => [addon_item]} }

  describe "#valid?" do
    context "with a valid quote version" do
      it "is valid for both scopes" do
        expect(described_class.new(quote_version:, billing_items:, scope: :update, payload_valid:)).to be_valid
        expect(described_class.new(quote_version:, billing_items:, scope: :approve, payload_valid:)).to be_valid
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
          expect(validator.errors).to eq({currency: ["value_is_mandatory"]})
        end
      end
    end

    context "when the currency is not ISO 4217" do
      let(:quote_version) { create(:quote_version, quote:, organization:, currency: "DOUBLOON") }

      it "returns an invalid_currency error" do
        expect(validator).not_to be_valid
        expect(validator.errors).to eq({currency: ["invalid_currency"]})
      end
    end

    context "when the add-on does not exist" do
      let(:addon_item) { super().merge("id" => "11111111-2222-3333-4444-555555555555") }

      it "returns an add_on_not_found error" do
        expect(validator).not_to be_valid
        expect(validator.errors).to eq({"billing_items.addons.0.id": ["add_on_not_found"]})
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
        expect(validator.errors).to eq({"billing_items.addons.0.id": ["add_on_not_found"]})
      end
    end

    context "when the payload is structurally invalid" do
      let(:payload_valid) { false }
      let(:addon_item) { super().merge("id" => "11111111-2222-3333-4444-555555555555") }
      let(:quote_version) { create(:quote_version, quote:, organization:, currency: "DOUBLOON") }

      it "skips per-addon checks but keeps quote version level ones" do
        expect(validator).not_to be_valid
        expect(validator.errors).to eq({currency: ["invalid_currency"]})
      end
    end

    context "when only from_datetime is present" do
      let(:payload) { super().merge("from_datetime" => "2026-01-01T00:00:00Z", "to_datetime" => nil) }

      it "requires to_datetime" do
        expect(validator).not_to be_valid
        expect(validator.errors).to eq({"billing_items.addons.0.payload.to_datetime": ["value_is_mandatory"]})
      end
    end

    context "when only to_datetime is present" do
      let(:payload) { super().merge("from_datetime" => nil, "to_datetime" => "2026-02-01T00:00:00Z") }

      it "requires from_datetime" do
        expect(validator).not_to be_valid
        expect(validator.errors).to eq({"billing_items.addons.0.payload.from_datetime": ["value_is_mandatory"]})
      end
    end

    context "when from_datetime is after to_datetime" do
      let(:payload) { super().merge("from_datetime" => "2026-02-01T00:00:00Z", "to_datetime" => "2026-01-01T00:00:00Z") }

      it "returns an invalid_date_range error" do
        expect(validator).not_to be_valid
        expect(validator.errors).to eq({"billing_items.addons.0.payload.from_datetime": ["invalid_date_range"]})
      end
    end

    context "when from_datetime equals to_datetime" do
      let(:payload) { super().merge("from_datetime" => "2026-01-01T00:00:00Z", "to_datetime" => "2026-01-01T00:00:00Z") }

      it "is valid" do
        expect(validator).to be_valid
      end
    end

    context "with errors on multiple addons" do
      let(:billing_items) do
        {
          "addons" => [
            addon_item,
            addon_item.merge("id" => "11111111-2222-3333-4444-555555555555")
          ]
        }
      end

      it "keys each error with the addon index" do
        expect(validator).not_to be_valid
        expect(validator.errors).to eq({"billing_items.addons.1.id": ["add_on_not_found"]})
      end
    end
  end
end
