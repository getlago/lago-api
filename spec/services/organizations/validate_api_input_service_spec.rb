# frozen_string_literal: true

require "rails_helper"

RSpec.describe Organizations::ValidateApiInputService do
  subject(:result) { described_class.call(params:) }

  let(:params) { {} }

  it "accepts omitted fields" do
    expect(result).to be_success
  end

  ["new-slug", nil].each do |slug|
    context "with slug set to #{slug.inspect}" do
      let(:params) { {slug:} }

      it "leaves string and presence validation to the model" do
        expect(result).to be_success
      end
    end
  end

  [true, false, 123].each do |slug|
    context "with slug set to #{slug.inspect}" do
      let(:params) { {slug:} }

      it "returns a validation error" do
        expect(result.error.messages).to eq(slug: ["value_is_invalid"])
      end
    end
  end
end
