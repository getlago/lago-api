# frozen_string_literal: true

require "rails_helper"

RSpec.describe QuoteVersions::Validators::OneOff::StructuralValidator do
  subject(:validator) { described_class.new(result, billing_items:, scope:) }

  let(:result) { BaseService::Result.new }
  let(:scope) { :update }
  let(:add_on_item) do
    {
      "id" => "48e59220-6722-49c1-8cdf-eacd040e2a56",
      "localId" => "3d08b2df-4e4c-4d58-b415-a525c1663735",
      "payload" => payload,
      "overrides" => overrides
    }
  end
  let(:overrides) do
    {
      "description" => "Setup fee",
      "units" => 2,
      "unitAmountCents" => 12_000,
      "totalAmountCents" => 12_000,
      "invoiceDisplayName" => "Custom setup",
      "fromDatetime" => "2026-01-05T00:00:00Z",
      "toDatetime" => "2026-01-20T00:00:00Z"
    }
  end
  let(:payload) do
    {
      "code" => "setup",
      "units" => 1,
      "unitAmountCents" => 10_000,
      "totalAmountCents" => 10_000,
      "invoiceDisplayName" => "One-time setup",
      "fromDatetime" => "2026-01-01T00:00:00Z",
      "toDatetime" => "2026-02-01T00:00:00Z"
    }
  end
  let(:billing_items) { {"addOns" => [add_on_item]} }

  describe "#valid?" do
    context "with a full valid payload" do
      it "is valid for both scopes" do
        expect(described_class.new(BaseService::Result.new, billing_items:, scope: :update)).to be_valid
        expect(described_class.new(BaseService::Result.new, billing_items:, scope: :approve)).to be_valid
      end
    end

    context "when billing_items is nil" do
      let(:billing_items) { nil }

      it "is valid at update scope" do
        expect(validator).to be_valid
        expect(result).to be_success
      end

      context "when the scope is approve" do
        let(:scope) { :approve }

        it "requires the addOns list" do
          expect(validator).not_to be_valid
          expect(result.error.messages).to eq({"billing_items.addOns": ["value_is_mandatory"]})
        end
      end
    end

    context "when billing_items is not an object" do
      let(:billing_items) { "bogus" }

      it "returns an invalid_type error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({billing_items: ["invalid_type"]})
      end
    end

    context "when billing_items contains an unknown root key" do
      let(:billing_items) { {"addOns" => [add_on_item], "subscriptions" => []} }

      it "returns an unsupported_key error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.subscriptions": ["unsupported_key"]})
      end
    end

    context "when the add_on contains an unknown key" do
      let(:add_on_item) { super().merge("taxCodes" => ["vat_20"]) }

      it "returns an unsupported_key error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.addOns.0.taxCodes": ["unsupported_key"]})
      end
    end

    context "when the payload contains unknown keys" do
      let(:payload) { super().merge("customField" => {"nested" => true}) }

      it "is valid" do
        expect(validator).to be_valid
      end
    end

    context "when the payload is missing" do
      let(:add_on_item) { super().except("payload") }

      it "returns a value_is_mandatory error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.addOns.0.payload": ["value_is_mandatory"]})
      end
    end

    context "when the payload is not an object" do
      let(:payload) { "bogus" }

      it "returns an invalid_type error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.addOns.0.payload": ["invalid_type"]})
      end
    end

    context "when overrides contains an unknown key" do
      let(:overrides) { super().merge("taxCodes" => ["vat_20"]) }

      it "returns an unsupported_key error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.addOns.0.overrides.taxCodes": ["unsupported_key"]})
      end
    end

    context "when overrides description is empty" do
      let(:overrides) { super().merge("description" => "") }

      it "returns an invalid_value error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.addOns.0.overrides.description": ["invalid_value"]})
      end
    end

    context "when overrides description is null" do
      let(:overrides) { super().merge("description" => nil) }

      it "returns an invalid_type error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.addOns.0.overrides.description": ["invalid_type"]})
      end
    end

    context "when overrides units is zero" do
      let(:overrides) { super().merge("units" => 0) }

      it "returns an invalid_value error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.addOns.0.overrides.units": ["invalid_value"]})
      end
    end

    context "when overrides units is a string" do
      let(:overrides) { super().merge("units" => "2") }

      it "returns an invalid_type error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.addOns.0.overrides.units": ["invalid_type"]})
      end
    end

    context "when overrides invoiceDisplayName is empty" do
      let(:overrides) { super().merge("invoiceDisplayName" => "") }

      it "returns an invalid_value error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.addOns.0.overrides.invoiceDisplayName": ["invalid_value"]})
      end
    end

    context "when overrides invoiceDisplayName is null" do
      let(:overrides) { super().merge("invoiceDisplayName" => nil) }

      it "returns an invalid_type error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.addOns.0.overrides.invoiceDisplayName": ["invalid_type"]})
      end
    end

    context "when overrides fromDatetime is not an ISO 8601 date-time" do
      let(:overrides) { super().merge("fromDatetime" => "not-a-date") }

      it "returns an invalid_format error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.addOns.0.overrides.fromDatetime": ["invalid_format"]})
      end
    end

    context "when overrides toDatetime has a wrong type" do
      let(:overrides) { super().merge("toDatetime" => 123) }

      it "returns an invalid_type error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.addOns.0.overrides.toDatetime": ["invalid_type"]})
      end
    end

    context "when overrides datetimes are null" do
      let(:overrides) { super().merge("fromDatetime" => nil, "toDatetime" => nil) }

      it "is valid" do
        expect(validator).to be_valid
      end
    end

    context "when the add_on identity is missing" do
      let(:add_on_item) { super().except("id", "localId") }

      it "requires id and localId at update scope" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq(
          {
            "billing_items.addOns.0.id": ["value_is_mandatory"],
            "billing_items.addOns.0.localId": ["value_is_mandatory"]
          }
        )
      end
    end

    context "when the add_on id is not a uuid" do
      let(:add_on_item) { super().merge("id" => "not-a-uuid") }

      it "returns an invalid_format error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.addOns.0.id": ["invalid_format"]})
      end
    end

    context "when localId is empty" do
      let(:add_on_item) { super().merge("localId" => "") }

      it "returns an invalid_value error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.addOns.0.localId": ["invalid_value"]})
      end
    end

    context "when units is zero" do
      let(:payload) { super().merge("units" => 0) }

      it "returns an invalid_value error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.addOns.0.payload.units": ["invalid_value"]})
      end
    end

    context "when units is a string" do
      let(:payload) { super().merge("units" => "1") }

      it "returns an invalid_type error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.addOns.0.payload.units": ["invalid_type"]})
      end
    end

    context "when amounts are negative or fractional" do
      let(:payload) { super().merge("unitAmountCents" => -1, "totalAmountCents" => 10.5) }

      it "returns invalid_value and invalid_type errors" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq(
          {
            "billing_items.addOns.0.payload.unitAmountCents": ["invalid_value"],
            "billing_items.addOns.0.payload.totalAmountCents": ["invalid_type"]
          }
        )
      end
    end

    context "when fromDatetime is not an ISO 8601 date-time" do
      let(:payload) { super().merge("fromDatetime" => "not-a-date") }

      it "returns an invalid_format error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.addOns.0.payload.fromDatetime": ["invalid_format"]})
      end
    end

    context "when toDatetime has a wrong type" do
      let(:payload) { super().merge("toDatetime" => 123) }

      it "returns an invalid_type error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.addOns.0.payload.toDatetime": ["invalid_type"]})
      end
    end

    context "when datetimes are null" do
      let(:payload) { super().merge("fromDatetime" => nil, "toDatetime" => nil) }

      it "is valid" do
        expect(validator).to be_valid
      end
    end

    context "when the scope is approve" do
      let(:scope) { :approve }

      context "when the addOns list is empty" do
        let(:billing_items) { {"addOns" => []} }

        it "returns an invalid_count error" do
          expect(validator).not_to be_valid
          expect(result.error.messages).to eq({"billing_items.addOns": ["invalid_count"]})
        end
      end

      context "when the payload is incomplete" do
        let(:payload) { {"invoiceDisplayName" => "One-time setup"} }

        it "requires the snapshot fields" do
          expect(validator).not_to be_valid
          expect(result.error.messages).to eq(
            {
              "billing_items.addOns.0.payload.code": ["value_is_mandatory"],
              "billing_items.addOns.0.payload.units": ["value_is_mandatory"],
              "billing_items.addOns.0.payload.unitAmountCents": ["value_is_mandatory"],
              "billing_items.addOns.0.payload.totalAmountCents": ["value_is_mandatory"]
            }
          )
        end
      end

      context "when the payload is incomplete at update scope" do
        let(:scope) { :update }
        let(:payload) { {"invoiceDisplayName" => "One-time setup"} }

        it "is valid" do
          expect(validator).to be_valid
        end
      end
    end

    context "with errors on multiple add_ons" do
      let(:billing_items) do
        {
          "addOns" => [
            add_on_item.merge("id" => "not-a-uuid"),
            add_on_item.merge("payload" => payload.merge("units" => -1))
          ]
        }
      end

      it "keys each error with the add_on index" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq(
          {
            "billing_items.addOns.0.id": ["invalid_format"],
            "billing_items.addOns.1.payload.units": ["invalid_value"]
          }
        )
      end
    end
  end
end
