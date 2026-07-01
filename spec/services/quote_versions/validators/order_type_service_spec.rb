# frozen_string_literal: true

require "rails_helper"

RSpec.describe "QuoteVersions::Validators::OrderTypeService" do
  subject(:validator) { validator_class.new(result, quote_version:, scope:) }

  let(:validator_class) do
    Class.new(QuoteVersions::Validators::OrderTypeService) do
      private

      def allowed_billing_item_keys
        ["items"]
      end

      def validate_billing_items
        validate_collection_shape("items")

        billing_item_array("items").each_with_index do |item, index|
          validate_nested_hash(item, index, collection_key: "items", nested_key: :payload)
          payload = safe_hash(item[:payload])
          next if payload[:units].blank?

          add_error(field: billing_item_field("items", item, index, :units), error_code: "unexpected_units")
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
  let(:billing_items) { {"items" => []} }

  it "is valid for an empty allowed collection" do
    expect(validator).to be_valid
    expect(result.error).to be_nil
  end

  context "when currency is invalid" do
    let(:currency) { "ABC" }

    it "adds a currency validation failure" do
      expect(validator).not_to be_valid
      expect(result.error.messages[:currency]).to eq(["value_is_invalid"])
    end
  end

  context "when billing_items is not an object" do
    let(:billing_items) { [] }

    it "adds a billing_items validation failure" do
      expect(validator).not_to be_valid
      expect(result.error.messages[:billing_items]).to eq(["value_is_invalid"])
    end
  end

  context "when billing_items has an unexpected key" do
    let(:billing_items) { {"unexpected" => []} }

    it "adds a billing_items validation failure" do
      expect(validator).not_to be_valid
      expect(result.error.messages[:billing_items]).to eq(["value_is_invalid"])
    end
  end

  context "when the collection is not an array" do
    let(:billing_items) { {"items" => "bad"} }

    it "adds a billing_items validation failure" do
      expect(validator).not_to be_valid
      expect(result.error.messages[:billing_items]).to eq(["value_is_invalid"])
    end
  end

  context "when several shape errors affect billing_items" do
    let(:billing_items) { {"items" => "bad", "unexpected" => []} }

    it "reports the shape error once" do
      expect(validator).not_to be_valid
      expect(result.error.messages[:billing_items]).to eq(["value_is_invalid"])
    end
  end

  context "when a nested payload is malformed" do
    let(:billing_items) { {"items" => [{"local_id" => "row-1", "payload" => "bad"}]} }

    it "adds a nested validation failure without raising" do
      valid = nil

      expect { valid = validator.valid? }.not_to raise_error
      expect(valid).to eq(false)
      expect(result.error.messages[:"items/row-1/payload"]).to eq(["value_is_invalid"])
    end
  end

  context "when a nested payload is valid" do
    let(:billing_items) { {"items" => [{"local_id" => "row-1", "payload" => {"units" => 1}}]} }

    it "uses local_id in field paths" do
      expect(validator).not_to be_valid
      expect(result.error.messages[:"items/row-1/units"]).to eq(["unexpected_units"])
    end
  end

  context "when local_id is absent" do
    let(:billing_items) { {"items" => [{"payload" => {"units" => 1}}]} }

    it "uses the original array index in field paths" do
      expect(validator).not_to be_valid
      expect(result.error.messages[:"items/0/units"]).to eq(["unexpected_units"])
    end
  end
end
