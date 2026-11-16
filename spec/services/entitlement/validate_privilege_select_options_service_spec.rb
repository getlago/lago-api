# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entitlement::ValidatePrivilegeSelectOptionsService do
  subject(:result) { described_class.call(value_type:, params:) }

  let(:params) { {select_options:}.with_indifferent_access }
  let(:select_options) { nil }

  shared_examples "a select_options failure" do |error_code|
    it "fails on select_options with #{error_code}" do
      expect(result).to be_failure
      expect(result.error).to be_a(BaseService::ValidationFailure)
      expect(result.error.messages).to eq(select_options: [error_code])
      expect(result.config).to be_nil
    end
  end

  context "when value_type is select" do
    let(:value_type) { "select" }

    context "with a list of strings" do
      let(:select_options) { ["a", "b"] }

      it "returns the config holding the options" do
        expect(result).to be_success
        expect(result.config).to eq("select_options" => ["a", "b"])
      end
    end

    context "when select_options is absent" do
      let(:params) { {}.with_indifferent_access }

      it_behaves_like "a select_options failure", "value_is_mandatory"
    end

    context "when select_options is nil" do
      let(:select_options) { nil }

      it_behaves_like "a select_options failure", "value_is_mandatory"
    end

    context "when select_options is empty" do
      let(:select_options) { [] }

      it_behaves_like "a select_options failure", "value_is_mandatory"
    end
  end

  context "when value_type is not select" do
    let(:value_type) { "string" }

    context "when select_options is absent" do
      let(:params) { {}.with_indifferent_access }

      it "returns an empty config" do
        expect(result).to be_success
        expect(result.config).to eq({})
      end
    end

    context "when select_options is nil" do
      let(:select_options) { nil }

      it "returns an empty config" do
        expect(result).to be_success
        expect(result.config).to eq({})
      end
    end

    context "when select_options is a list of strings" do
      let(:select_options) { ["a"] }

      it_behaves_like "a select_options failure", "value_must_be_blank"
    end

    context "when select_options is empty" do
      let(:select_options) { [] }

      it_behaves_like "a select_options failure", "value_must_be_blank"
    end
  end

  %w[select string].each do |type|
    context "when value_type is #{type}" do
      let(:value_type) { type }

      ["foo", 1, {"a" => "b"}, [{"a" => 1}], [["a"]], [1, 2], ["a", 1]].each do |options|
        context "when select_options is #{options.inspect}" do
          let(:select_options) { options }

          it_behaves_like "a select_options failure", "value_is_invalid"
        end
      end
    end
  end
end
