# frozen_string_literal: true

require "rails_helper"

RSpec.describe Customers::ValidateApiInputService do
  subject(:result) { described_class.call(params:) }

  let(:params) { {} }

  it "accepts omitted settings" do
    expect(result).to be_success
  end

  %w[inherit skip finalize].each do |value|
    context "with finalize_zero_amount_invoice set to #{value}" do
      let(:params) { {finalize_zero_amount_invoice: value} }

      it "accepts the value" do
        expect(result).to be_success
      end
    end
  end

  [false, 123, "invalid"].each do |value|
    context "with finalize_zero_amount_invoice set to #{value.inspect}" do
      let(:params) { {finalize_zero_amount_invoice: value} }

      it "returns a validation error" do
        expect(result).to be_failure
        expect(result.error.messages).to eq(finalize_zero_amount_invoice: ["invalid_value"])
      end
    end
  end

  context "with repeated integration types" do
    let(:params) { {integration_customers: [{integration_type: "anrok"}, {integration_type: "anrok"}]} }

    it "rejects the duplicates" do
      expect(result).to be_failure
      expect(result.error.messages).to eq(integration_customers: ["invalid_count_per_integration_type"])
    end
  end

  context "with different integration types" do
    let(:params) { {integration_customers: [{integration_type: "anrok"}, {integration_type: "avalara"}]} }

    it "accepts the settings" do
      expect(result).to be_success
    end
  end
end
