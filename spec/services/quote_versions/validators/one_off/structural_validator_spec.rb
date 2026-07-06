# frozen_string_literal: true

require "rails_helper"

RSpec.describe QuoteVersions::Validators::OneOff::StructuralValidator do
  subject(:validator) { described_class.new(billing_items:, scope:) }

  let(:scope) { :update }
  let(:addon_item) do
    {
      "id" => "48e59220-6722-49c1-8cdf-eacd040e2a56",
      "local_id" => "3d08b2df-4e4c-4d58-b415-a525c1663735",
      "payload" => payload,
      "overrides" => {
        "unit_amount_cents" => 12_000,
        "total_amount_cents" => 12_000
      }
    }
  end
  let(:payload) do
    {
      "code" => "setup",
      "units" => 1,
      "unit_amount_cents" => 10_000,
      "total_amount_cents" => 10_000,
      "invoice_display_name" => "One-time setup",
      "from_datetime" => "2026-01-01T00:00:00Z",
      "to_datetime" => "2026-02-01T00:00:00Z"
    }
  end
  let(:billing_items) { {"addons" => [addon_item]} }

  describe "#valid?" do
    context "with a full valid payload" do
      it "is valid for both scopes" do
        expect(described_class.new(billing_items:, scope: :update)).to be_valid
        expect(described_class.new(billing_items:, scope: :approve)).to be_valid
      end
    end

    context "when billing_items is nil" do
      let(:billing_items) { nil }

      it "is valid at update scope" do
        expect(validator).to be_valid
        expect(validator.errors).to eq({})
      end

      context "when the scope is approve" do
        let(:scope) { :approve }

        it "requires the addons list" do
          expect(validator).not_to be_valid
          expect(validator.errors).to eq({"billing_items.addons": ["value_is_mandatory"]})
        end
      end
    end

    context "when billing_items is not an object" do
      let(:billing_items) { "bogus" }

      it "returns an invalid_type error" do
        expect(validator).not_to be_valid
        expect(validator.errors).to eq({billing_items: ["invalid_type"]})
      end
    end

    context "when billing_items contains an unknown root key" do
      let(:billing_items) { {"addons" => [addon_item], "subscriptions" => []} }

      it "returns an unsupported_key error" do
        expect(validator).not_to be_valid
        expect(validator.errors).to eq({"billing_items.subscriptions": ["unsupported_key"]})
      end
    end

    context "when the payload contains tax_codes" do
      let(:payload) { super().merge("tax_codes" => ["vat_20"]) }

      it "returns an unsupported_key error" do
        expect(validator).not_to be_valid
        expect(validator.errors).to eq({"billing_items.addons.0.payload.tax_codes": ["unsupported_key"]})
      end
    end

    context "when overrides contains an unknown key" do
      let(:addon_item) { super().merge("overrides" => {"units" => 2}) }

      it "returns an unsupported_key error" do
        expect(validator).not_to be_valid
        expect(validator.errors).to eq({"billing_items.addons.0.overrides.units": ["unsupported_key"]})
      end
    end

    context "when the addon identity is missing" do
      let(:addon_item) { super().except("id", "local_id") }

      it "requires id and local_id at update scope" do
        expect(validator).not_to be_valid
        expect(validator.errors).to eq(
          {
            "billing_items.addons.0.id": ["value_is_mandatory"],
            "billing_items.addons.0.local_id": ["value_is_mandatory"]
          }
        )
      end
    end

    context "when the addon id is not a uuid" do
      let(:addon_item) { super().merge("id" => "not-a-uuid") }

      it "returns an invalid_format error" do
        expect(validator).not_to be_valid
        expect(validator.errors).to eq({"billing_items.addons.0.id": ["invalid_format"]})
      end
    end

    context "when local_id is empty" do
      let(:addon_item) { super().merge("local_id" => "") }

      it "returns an invalid_value error" do
        expect(validator).not_to be_valid
        expect(validator.errors).to eq({"billing_items.addons.0.local_id": ["invalid_value"]})
      end
    end

    context "when units is zero" do
      let(:payload) { super().merge("units" => 0) }

      it "returns an invalid_value error" do
        expect(validator).not_to be_valid
        expect(validator.errors).to eq({"billing_items.addons.0.payload.units": ["invalid_value"]})
      end
    end

    context "when units is a string" do
      let(:payload) { super().merge("units" => "1") }

      it "returns an invalid_type error" do
        expect(validator).not_to be_valid
        expect(validator.errors).to eq({"billing_items.addons.0.payload.units": ["invalid_type"]})
      end
    end

    context "when amounts are negative or fractional" do
      let(:payload) { super().merge("unit_amount_cents" => -1, "total_amount_cents" => 10.5) }

      it "returns invalid_value and invalid_type errors" do
        expect(validator).not_to be_valid
        expect(validator.errors).to eq(
          {
            "billing_items.addons.0.payload.unit_amount_cents": ["invalid_value"],
            "billing_items.addons.0.payload.total_amount_cents": ["invalid_type"]
          }
        )
      end
    end

    context "when from_datetime is not an ISO 8601 date-time" do
      let(:payload) { super().merge("from_datetime" => "not-a-date") }

      it "returns an invalid_format error" do
        expect(validator).not_to be_valid
        expect(validator.errors).to eq({"billing_items.addons.0.payload.from_datetime": ["invalid_format"]})
      end
    end

    context "when to_datetime has a wrong type" do
      let(:payload) { super().merge("to_datetime" => 123) }

      it "returns an invalid_type error" do
        expect(validator).not_to be_valid
        expect(validator.errors).to eq({"billing_items.addons.0.payload.to_datetime": ["invalid_type"]})
      end
    end

    context "when datetimes are null" do
      let(:payload) { super().merge("from_datetime" => nil, "to_datetime" => nil) }

      it "is valid" do
        expect(validator).to be_valid
      end
    end

    context "when the scope is approve" do
      let(:scope) { :approve }

      context "when the addons list is empty" do
        let(:billing_items) { {"addons" => []} }

        it "returns an invalid_count error" do
          expect(validator).not_to be_valid
          expect(validator.errors).to eq({"billing_items.addons": ["invalid_count"]})
        end
      end

      context "when an addon has no payload" do
        let(:addon_item) { super().except("payload") }

        it "requires the payload" do
          expect(validator).not_to be_valid
          expect(validator.errors).to eq({"billing_items.addons.0.payload": ["value_is_mandatory"]})
        end
      end

      context "when the payload is incomplete" do
        let(:payload) { {"invoice_display_name" => "One-time setup"} }

        it "requires the snapshot fields" do
          expect(validator).not_to be_valid
          expect(validator.errors).to eq(
            {
              "billing_items.addons.0.payload.code": ["value_is_mandatory"],
              "billing_items.addons.0.payload.units": ["value_is_mandatory"],
              "billing_items.addons.0.payload.unit_amount_cents": ["value_is_mandatory"],
              "billing_items.addons.0.payload.total_amount_cents": ["value_is_mandatory"]
            }
          )
        end
      end

      context "when the payload is incomplete at update scope" do
        let(:scope) { :update }
        let(:payload) { {"invoice_display_name" => "One-time setup"} }

        it "is valid" do
          expect(validator).to be_valid
        end
      end
    end

    context "with errors on multiple addons" do
      let(:billing_items) do
        {
          "addons" => [
            addon_item.merge("id" => "not-a-uuid"),
            addon_item.merge("payload" => payload.merge("units" => -1))
          ]
        }
      end

      it "keys each error with the addon index" do
        expect(validator).not_to be_valid
        expect(validator.errors).to eq(
          {
            "billing_items.addons.0.id": ["invalid_format"],
            "billing_items.addons.1.payload.units": ["invalid_value"]
          }
        )
      end
    end
  end
end
