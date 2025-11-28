# frozen_string_literal: true

require "rails_helper"

RSpec.describe Metadata::DeleteItemKeyService do
  subject(:service) { described_class.new(item, key:) }

  let(:organization) { create(:organization) }
  let(:owner) { create(:credit_note, organization:) }
  let(:item) { create(:item_metadata, owner:, organization:, value:) }
  let(:value) { {"foo" => "bar", "baz" => "qux"} }
  let(:key) { "foo" }

  describe "#call" do
    context "when key exists" do
      it "removes the key from metadata" do
        result = service.call

        expect(result).to be_success
        expect(item.reload.value).to eq({"baz" => "qux"})
      end

      it "returns deleted value" do
        result = service.call

        expect(result.deleted_value).to eq("bar")
      end

      it "sets changed to true" do
        result = service.call

        expect(result.changed).to be(true)
      end
    end

    context "when key does not exist" do
      let(:key) { "nonexistent" }

      it "does not modify metadata" do
        result = service.call

        expect(result).to be_success
        expect(item.reload.value).to eq({"foo" => "bar", "baz" => "qux"})
      end

      it "returns nil as deleted value" do
        result = service.call

        expect(result.deleted_value).to be_nil
      end

      it "sets changed to false" do
        result = service.call

        expect(result.changed).to be(false)
      end
    end

    context "when key is a symbol" do
      let(:key) { :foo }

      it "converts key to string and removes it" do
        result = service.call

        expect(result).to be_success
        expect(item.reload.value).to eq({"baz" => "qux"})
        expect(result.deleted_value).to eq("bar")
        expect(result.changed).to be(true)
      end
    end

    context "when removing the last key" do
      let(:value) { {"foo" => "bar"} }

      it "leaves empty hash" do
        result = service.call

        expect(result).to be_success
        expect(item.reload.value).to eq({})
      end
    end

    context "when value contains nil" do
      let(:value) { {"foo" => nil, "baz" => "qux"} }

      it "removes key with nil value" do
        result = service.call

        expect(result).to be_success
        expect(item.reload.value).to eq({"baz" => "qux"})
        expect(result.deleted_value).to be_nil
        expect(result.changed).to be(true)
      end
    end

    context "when value contains empty string" do
      let(:value) { {"foo" => "", "baz" => "qux"} }

      it "removes key with empty string" do
        result = service.call

        expect(result).to be_success
        expect(item.reload.value).to eq({"baz" => "qux"})
        expect(result.deleted_value).to eq("")
        expect(result.changed).to be(true)
      end
    end
  end
end
