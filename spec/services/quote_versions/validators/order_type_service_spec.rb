# frozen_string_literal: true

require "rails_helper"

RSpec.describe "QuoteVersions::Validators::OrderTypeService" do
  subject(:validator) { validator_class.new(result, quote_version:, scope:) }

  let(:test_schema) do
    JSONSchemer.schema(
      {
        "type" => "object",
        "properties" => {
          "currency" => {"enum" => ["EUR", nil], "x-error" => {"*" => "value_is_invalid"}},
          "billing_items" => {
            "type" => "object",
            "additionalProperties" => {"not" => {}, "x-error" => {"*" => "value_is_invalid"}},
            "x-error" => {"*" => "value_is_invalid"},
            "properties" => {
              "items" => {
                "type" => "array",
                "minItems" => 1,
                "x-error" => {"minItems" => "items_required", "*" => "value_is_invalid"},
                "items" => {
                  "type" => "object",
                  "x-error" => {"*" => "value_is_invalid"},
                  "properties" => {
                    "name" => {"type" => ["string", "null"], "x-error" => {"*" => "value_is_invalid"}}
                  }
                }
              }
            }
          }
        }
      }
    )
  end

  let(:validator_class) do
    schema = test_schema

    Class.new(QuoteVersions::Validators::OrderTypeService) do
      attr_reader :business_validated

      define_method(:schema) { schema }

      private

      def allowed_billing_item_keys
        ["items"]
      end

      def validate_billing_items
        @business_validated = true

        billing_item_array("items").each_with_index do |item, index|
          if item["name"].blank?
            add_error(field: billing_item_field("items", item, index, :name), error_code: "value_is_mandatory")
          end
        end
      end
    end
  end

  let(:result) { BaseService::Result.new }
  let(:organization) { create(:organization) }
  let(:quote) { create(:quote, organization:, order_type: :one_off) }
  let(:quote_version) { build(:quote_version, quote:, organization:, currency:, billing_items:) }
  let(:currency) { "EUR" }
  let(:scope) { :update }
  let(:billing_items) { {"items" => [{"local_id" => "row-1", "name" => "Item"}]} }

  it "is valid and runs the business validations" do
    expect(validator).to be_valid
    expect(result.error).to be_nil
    expect(validator.business_validated).to eq(true)
  end

  context "when the currency is lowercase" do
    let(:currency) { "eur" }

    it "normalizes it on the quote version" do
      expect(validator).to be_valid
      expect(quote_version.currency).to eq("EUR")
    end
  end

  context "when the currency is not in the schema" do
    let(:currency) { "usd" }

    it "adds a currency validation failure and keeps the original value" do
      expect(validator).not_to be_valid
      expect(result.error.messages[:currency]).to eq(["value_is_invalid"])
      expect(quote_version.currency).to eq("usd")
    end
  end

  context "when the currency is blank" do
    let(:currency) { "   " }

    it "is structurally valid and leaves the value untouched" do
      expect(validator).to be_valid
      expect(quote_version.currency).to eq("   ")
    end
  end

  context "when the document is structurally invalid" do
    let(:billing_items) { {"unexpected" => []} }

    it "fails fast without running the business validations" do
      expect(validator).not_to be_valid
      expect(result.error.messages[:billing_items]).to eq(["value_is_invalid"])
      expect(validator.business_validated).to be_nil
    end
  end

  context "when the collection is empty" do
    let(:billing_items) { {"items" => []} }

    it "anchors the schema error code to the collection key" do
      expect(validator).not_to be_valid
      expect(result.error.messages[:items]).to eq(["items_required"])
    end
  end

  context "when an item attribute is structurally invalid and local_id is blank" do
    let(:billing_items) { {"items" => [{"local_id" => "", "name" => 1}]} }

    it "keys the error by the array index" do
      expect(validator).not_to be_valid
      expect(result.error.messages[:"items/0/name"]).to eq(["value_is_invalid"])
    end
  end

  context "when a business validation fails" do
    let(:billing_items) { {"items" => [{"local_id" => "row-1"}, {}]} }

    it "aggregates errors keyed by local_id or index" do
      expect(validator).not_to be_valid
      expect(result.error.messages[:"items/row-1/name"]).to eq(["value_is_mandatory"])
      expect(result.error.messages[:"items/1/name"]).to eq(["value_is_mandatory"])
    end
  end
end
