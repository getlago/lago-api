# frozen_string_literal: true

require "rails_helper"

RSpec.describe BaseResult do
  subject(:result) { described_class.new }

  it_behaves_like "a result object"

  describe "#[]" do
    let(:result_class) { described_class[:property] }

    it { expect(result_class.new).to be_kind_of(described_class) }

    it "defines the attributes" do
      expect(result_class.new).to respond_to(:property)
      expect(result_class.new).to respond_to(:property=)
    end

    context "with multiple properties" do
      let(:result_class) { described_class[:property, :another_property] }

      it "defines the attributes" do
        expect(result_class.new).to respond_to(:property)
        expect(result_class.new).to respond_to(:property=)
        expect(result_class.new).to respond_to(:another_property)
        expect(result_class.new).to respond_to(:another_property=)
      end
    end
  end
end
