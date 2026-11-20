# frozen_string_literal: true

require "rails_helper"

RSpec.describe StringValidator do
  subject(:validator) { described_class.new(attributes: [:code]) }

  let(:model) { Entitlement::Privilege.new(code:) }

  ["max_admins", "", "  ", :max_admins].each do |value|
    context "when the code is the string #{value.inspect}" do
      let(:code) { value }

      it "is valid" do
        validator.validate(model)
        expect(model.errors[:code]).to be_empty
      end
    end
  end

  context "when the code is nil" do
    let(:code) { nil }

    it "is valid, presence is checked elsewhere" do
      validator.validate(model)
      expect(model.errors[:code]).to be_empty
    end
  end

  [["a number", 123], ["a boolean", true], ["false", false], ["an array", ["a"]], ["a hash", {a: 1}]].each do |label, value|
    context "when the code is #{label}" do
      let(:code) { value }

      it "adds an invalid error" do
        validator.validate(model)
        expect(model.errors.details[:code]).to eq([{error: :invalid}])
      end
    end
  end

  context "when the record has no attribute with a raw value" do
    subject(:validator) { described_class.new(attributes: [:name]) }

    let(:model) { Struct.new(:name) { include ActiveModel::Validations }.new(1) }

    it "checks the value itself" do
      validator.validate(model)
      expect(model.errors.details[:name]).to eq([{error: :invalid}])
    end
  end
end
