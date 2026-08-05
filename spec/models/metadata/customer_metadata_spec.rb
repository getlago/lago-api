# frozen_string_literal: true

require "rails_helper"

RSpec.describe Metadata::CustomerMetadata do
  subject(:metadata) { described_class.new(attributes) }

  let(:customer) { create(:customer) }
  let(:key) { "hello" }
  let(:value) { "abcdef" }
  let(:attributes) do
    {key:, value:, customer:, display_in_invoice: true, organization: customer.organization}
  end

  it { is_expected.to belong_to(:organization) }

  describe "key validations" do
    context "when uniqueness condition is satisfied", :tag do
      it { expect(metadata).to be_valid }
    end

    context "when key is not unique" do
      let(:old_metadata) { create(:customer_metadata, customer:, key: "hello") }

      before { old_metadata }

      it { expect(metadata).not_to be_valid }
    end

    context "when key length is invalid" do
      let(:key) { "hello-hello-hello-hello-hello" }

      it { expect(metadata).not_to be_valid }
    end
  end

  describe "value validations" do
    context "when length constraint is satisfied", :tag do
      it { expect(metadata).to be_valid }
    end

    context "when value length is invalid" do
      let(:value) { "a" * 101 }

      it { expect(metadata).not_to be_valid }
    end
  end

  describe "normalizations" do
    let(:key) { "he\u0000llo" }
    let(:value) { "wo\u0000rld" }

    it "strips null bytes from key and value" do
      expect(metadata.key).to eq("hello")
      expect(metadata.value).to eq("world")
    end
  end
end
