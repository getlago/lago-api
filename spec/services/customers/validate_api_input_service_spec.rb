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

  %w[current_period_end next_period_start].each do |value|
    context "with the periodic invoice anchor set to #{value}" do
      let(:params) { {billing_configuration: {subscription_invoice_issuing_date_anchor: value}} }

      it "accepts the value" do
        expect(result).to be_success
      end
    end
  end

  [false, 123, "invalid"].each do |value|
    context "with the periodic invoice anchor set to #{value.inspect}" do
      let(:params) { {billing_configuration: {subscription_invoice_issuing_date_anchor: value}} }

      it "returns a validation error under the REST field name" do
        expect(result).to be_failure
        expect(result.error.messages).to eq(periodic_invoice_anchor: ["value_is_invalid"])
      end
    end
  end

  %w[keep_anchor align_with_finalization_date].each do |value|
    context "with the periodic invoice adjustment set to #{value}" do
      let(:params) { {billing_configuration: {subscription_invoice_issuing_date_adjustment: value}} }

      it "accepts the value" do
        expect(result).to be_success
      end
    end
  end

  [false, 123, "invalid"].each do |value|
    context "with the periodic invoice adjustment set to #{value.inspect}" do
      let(:params) { {billing_configuration: {subscription_invoice_issuing_date_adjustment: value}} }

      it "returns a validation error under the REST field name" do
        expect(result).to be_failure
        expect(result.error.messages).to eq(periodic_invoice_adjustment: ["value_is_invalid"])
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
