# frozen_string_literal: true

require "rails_helper"

RSpec.describe QuoteVersions::Validators::SchemaErrorMapper do
  subject(:mapper) { described_class.new(document:) }

  let(:document) do
    {
      "currency" => "EUR",
      "billing_items" => {
        "add_ons" => [
          {"local_id" => "row-1", "payload" => {"units" => 1}, "overrides" => {}}
        ]
      }
    }
  end

  def schemer_error(data_pointer:, type:, error: "value_is_invalid", details: nil)
    {"data_pointer" => data_pointer, "type" => type, "error" => error, "details" => details}
  end

  describe "#call" do
    it "anchors a top-level error to its property" do
      errors = [schemer_error(data_pointer: "/currency", type: "enum")]

      expect(mapper.call(errors)).to eq([[:currency, "value_is_invalid"]])
    end

    it "passes the schema-declared code through" do
      errors = [schemer_error(data_pointer: "/currency", type: "not", error: "value_is_mandatory")]

      expect(mapper.call(errors)).to eq([[:currency, "value_is_mandatory"]])
    end

    it "anchors a billing_items type failure to billing_items" do
      errors = [schemer_error(data_pointer: "/billing_items", type: "object")]

      expect(mapper.call(errors)).to eq([[:billing_items, "value_is_invalid"]])
    end

    it "rolls an unexpected billing_items key up to billing_items" do
      errors = [schemer_error(data_pointer: "/billing_items/addons", type: "not")]

      expect(mapper.call(errors)).to eq([[:billing_items, "value_is_invalid"]])
    end

    it "anchors a missing collection to the collection key" do
      errors = [
        schemer_error(
          data_pointer: "/billing_items",
          type: "required",
          error: "add_ons_required",
          details: {"missing_keys" => ["add_ons"]}
        )
      ]

      expect(mapper.call(errors)).to eq([[:add_ons, "add_ons_required"]])
    end

    it "anchors a minItems failure to the collection key" do
      errors = [schemer_error(data_pointer: "/billing_items/add_ons", type: "minItems", error: "add_ons_required")]

      expect(mapper.call(errors)).to eq([[:add_ons, "add_ons_required"]])
    end

    it "rolls a non-array collection up to billing_items" do
      errors = [schemer_error(data_pointer: "/billing_items/add_ons", type: "array")]

      expect(mapper.call(errors)).to eq([[:billing_items, "value_is_invalid"]])
    end

    it "rolls a non-object item up to billing_items" do
      errors = [schemer_error(data_pointer: "/billing_items/add_ons/0", type: "object")]

      expect(mapper.call(errors)).to eq([[:billing_items, "value_is_invalid"]])
    end

    it "anchors a nested object failure to the item field" do
      errors = [schemer_error(data_pointer: "/billing_items/add_ons/0/payload", type: "object")]

      expect(mapper.call(errors)).to eq([[:"add_ons/row-1/payload", "value_is_invalid"]])
    end

    it "expands missing item keys to one mandatory entry per key" do
      errors = [
        schemer_error(
          data_pointer: "/billing_items/add_ons/0/payload",
          type: "required",
          error: "value_is_mandatory",
          details: {"missing_keys" => ["units", "unit_amount_cents"]}
        )
      ]

      expect(mapper.call(errors)).to eq([
        [:"add_ons/row-1/units", "value_is_mandatory"],
        [:"add_ons/row-1/unit_amount_cents", "value_is_mandatory"]
      ])
    end

    it "anchors an attribute failure to the item field, dropping the payload segment" do
      errors = [schemer_error(data_pointer: "/billing_items/add_ons/0/payload/units", type: "exclusiveMinimum")]

      expect(mapper.call(errors)).to eq([[:"add_ons/row-1/units", "value_is_invalid"]])
    end

    context "when the item has no usable local_id" do
      let(:document) do
        {
          "currency" => "EUR",
          "billing_items" => {
            "add_ons" => [
              {"local_id" => "", "payload" => {}, "overrides" => {}},
              "garbage"
            ]
          }
        }
      end

      it "falls back to the array index" do
        errors = [
          schemer_error(data_pointer: "/billing_items/add_ons/0/payload/units", type: "exclusiveMinimum"),
          schemer_error(data_pointer: "/billing_items/add_ons/1/overrides", type: "object")
        ]

        expect(mapper.call(errors)).to eq([
          [:"add_ons/0/units", "value_is_invalid"],
          [:"add_ons/1/overrides", "value_is_invalid"]
        ])
      end
    end

    it "dedups billing_items errors" do
      errors = [
        schemer_error(data_pointer: "/billing_items/add_ons", type: "array"),
        schemer_error(data_pointer: "/billing_items/extra", type: "not")
      ]

      expect(mapper.call(errors)).to eq([[:billing_items, "value_is_invalid"]])
    end

    it "suppresses required errors when billing_items is malformed" do
      errors = [
        schemer_error(data_pointer: "/currency", type: "not", error: "value_is_mandatory"),
        schemer_error(data_pointer: "/billing_items/add_ons", type: "array"),
        schemer_error(data_pointer: "/billing_items/add_ons", type: "minItems", error: "add_ons_required")
      ]

      expect(mapper.call(errors)).to eq([
        [:currency, "value_is_mandatory"],
        [:billing_items, "value_is_invalid"]
      ])
    end

    it "keeps required errors when billing_items itself is well-formed" do
      errors = [
        schemer_error(
          data_pointer: "/billing_items",
          type: "required",
          error: "add_ons_required",
          details: {"missing_keys" => ["add_ons"]}
        ),
        schemer_error(data_pointer: "/currency", type: "not", error: "value_is_mandatory")
      ]

      expect(mapper.call(errors)).to eq([
        [:add_ons, "add_ons_required"],
        [:currency, "value_is_mandatory"]
      ])
    end
  end
end
