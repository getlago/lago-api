# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::Metadata::Input do
  subject { described_class }

  it "has the expected arguments" do
    expect(subject).to accept_argument(:key).of_type("String!")
    expect(subject).to accept_argument(:value).of_type("String")
  end

  describe "ARGUMENT_OPTIONS" do
    let(:prepare) { described_class::ARGUMENT_OPTIONS[:prepare] }
    let(:validator_config) { described_class::ARGUMENT_OPTIONS[:validates] }
    let(:validated_object) { double("Validated Object") } # rubocop:disable RSpec/VerifiedDoubles
    let(:validator) do
      Validators::UniqueByFieldValidator.new(**validator_config.values.first, validated: validated_object)
    end

    describe "prepare" do
      it "converts array of items to hash" do
        input = [{key: "foo", value: "bar"}, {key: "baz", value: "qux"}]
        expect(prepare.call(input, nil)).to eq({"foo" => "bar", "baz" => "qux"})
      end

      it "returns nil for nil input" do
        expect(prepare.call(nil, nil)).to be_nil
      end

      it "returns empty hash for empty array" do
        expect(prepare.call([], nil)).to eq({})
      end

      it "handles nil value" do
        input = [{key: "foo", value: nil}]
        expect(prepare.call(input, nil)).to eq({"foo" => nil})
      end

      it "handles empty string key" do
        input = [{key: "", value: "bar"}]
        expect(prepare.call(input, nil)).to eq({"" => "bar"})
      end

      it "handles empty string value" do
        input = [{key: "foo", value: ""}]
        expect(prepare.call(input, nil)).to eq({"foo" => ""})
      end

      it "overwrites duplicate keys with last value" do
        input = [{key: "foo", value: "first"}, {key: "foo", value: "second"}]
        expect(prepare.call(input, nil)).to eq({"foo" => "second"})
      end

      it "handles mixed edge cases" do
        input = [
          {key: "foo", value: nil},
          {key: "", value: "baz"},
          {key: "bar", value: ""},
          {key: "bar", value: "qux"}
        ]
        expect(prepare.call(input, nil)).to eq({
          "foo" => nil,
          "" => "baz",
          "bar" => "qux"
        })
      end
    end

    describe "validates" do
      it "uses UniqueByFieldValidator with field_name: :key" do
        expect(validator_config).to eq({
          Validators::UniqueByFieldValidator => {field_name: :key}
        })
      end

      it "returns error for duplicate keys" do
        input = [{key: "foo", value: "bar"}, {key: "foo", value: "baz"}]
        expect(validator.validate(nil, nil, input)).to eq("duplicated_field")
      end

      it "returns nil for unique keys" do
        input = [{key: "foo", value: "bar"}, {key: "baz", value: "qux"}]
        expect(validator.validate(nil, nil, input)).to be_nil
      end

      it "returns nil for empty array" do
        expect(validator.validate(nil, nil, [])).to be_nil
      end

      it "returns nil for nil keys (nil keys are not duplicates)" do
        input = [{key: nil, value: "bar"}, {key: nil, value: "baz"}]
        expect(validator.validate(nil, nil, input)).to be_nil
      end
    end
  end
end
