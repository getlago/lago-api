# frozen_string_literal: true

require "rails_helper"

RSpec.describe Validators::JsonSchemaValidator do
  subject(:validator) { described_class.new(data, schema:) }

  let(:schema) do
    {
      "name" => {type: String},
      "age" => {type: Integer},
      "address" => {
        type: Hash,
        schema: {
          "street" => {type: String},
          "zip" => {type: String}
        }
      },
      "tags" => {
        type: Array,
        items: {
          type: Hash,
          schema: {
            "label" => {type: String},
            "priority" => {type: Integer}
          }
        }
      }
    }
  end

  describe "#valid?" do
    context "with valid data" do
      let(:data) do
        {
          "name" => "Alice",
          "age" => 30,
          "address" => {"street" => "123 Main St", "zip" => "12345"},
          "tags" => [{"label" => "vip", "priority" => 1}]
        }
      end

      it "returns true" do
        expect(validator).to be_valid
        expect(validator.errors).to be_empty
      end
    end

    context "with nil values for optional keys" do
      let(:data) { {"name" => "Alice", "age" => nil, "address" => nil, "tags" => nil} }

      it "returns true" do
        expect(validator).to be_valid
      end
    end

    context "with absent keys" do
      let(:data) { {"name" => "Alice"} }

      it "returns true" do
        expect(validator).to be_valid
      end
    end

    context "with empty string for a String field" do
      let(:data) { {"name" => ""} }

      it "returns true because empty string is still a String" do
        expect(validator).to be_valid
      end
    end

    context "with empty string for a non-String field" do
      let(:data) { {"age" => ""} }

      it "returns false with invalid_type error" do
        expect(validator).not_to be_valid
        expect(validator.errors).to include({path: "age", error: "invalid_type"})
      end
    end

    context "with empty hash for a Hash field" do
      let(:data) { {"address" => {}} }

      it "returns true because empty hash is still a Hash" do
        expect(validator).to be_valid
      end
    end

    context "with empty hash for a non-Hash field" do
      let(:data) { {"name" => {}} }

      it "returns false with invalid_type error" do
        expect(validator).not_to be_valid
        expect(validator.errors).to include({path: "name", error: "invalid_type"})
      end
    end

    context "with empty arrays" do
      let(:data) { {"tags" => []} }

      it "returns true" do
        expect(validator).to be_valid
      end
    end

    context "with unknown top-level key" do
      let(:data) { {"name" => "Alice", "unknown" => "value"} }

      it "returns false with unknown_key error" do
        expect(validator).not_to be_valid
        expect(validator.errors).to include({path: "unknown", error: "unknown_key"})
      end
    end

    context "with wrong type at top level" do
      let(:data) { {"name" => 123} }

      it "returns false with invalid_type error" do
        expect(validator).not_to be_valid
        expect(validator.errors).to include({path: "name", error: "invalid_type"})
      end
    end

    context "with wrong type for nested hash" do
      let(:data) { {"address" => "not a hash"} }

      it "returns false with invalid_type error" do
        expect(validator).not_to be_valid
        expect(validator.errors).to include({path: "address", error: "invalid_type"})
      end
    end

    context "with unknown key in nested hash" do
      let(:data) { {"address" => {"street" => "123 Main", "zip" => "12345", "bogus" => true}} }

      it "returns false with unknown_key error" do
        expect(validator).not_to be_valid
        expect(validator.errors).to include({path: "address.bogus", error: "unknown_key"})
      end
    end

    context "with wrong type in nested hash" do
      let(:data) { {"address" => {"street" => 999}} }

      it "returns false with invalid_type error" do
        expect(validator).not_to be_valid
        expect(validator.errors).to include({path: "address.street", error: "invalid_type"})
      end
    end

    context "with wrong type for array" do
      let(:data) { {"tags" => "not an array"} }

      it "returns false with invalid_type error" do
        expect(validator).not_to be_valid
        expect(validator.errors).to include({path: "tags", error: "invalid_type"})
      end
    end

    context "with wrong type for array item" do
      let(:data) { {"tags" => ["not a hash"]} }

      it "returns false with invalid_type error" do
        expect(validator).not_to be_valid
        expect(validator.errors).to include({path: "tags[0]", error: "invalid_type"})
      end
    end

    context "with unknown key in array item" do
      let(:data) { {"tags" => [{"label" => "vip", "unknown" => true}]} }

      it "returns false with unknown_key error" do
        expect(validator).not_to be_valid
        expect(validator.errors).to include({path: "tags[0].unknown", error: "unknown_key"})
      end
    end

    context "with wrong type in array item" do
      let(:data) { {"tags" => [{"label" => "vip", "priority" => "high"}]} }

      it "returns false with invalid_type error" do
        expect(validator).not_to be_valid
        expect(validator.errors).to include({path: "tags[0].priority", error: "invalid_type"})
      end
    end

    context "with multiple errors" do
      let(:data) { {"unknown_key" => "x", "name" => 123} }

      it "collects all errors" do
        expect(validator).not_to be_valid
        expect(validator.errors.length).to eq(2)
      end
    end
  end
end
