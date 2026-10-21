# frozen_string_literal: true

require "rails_helper"

RSpec.describe Customers::MergeEuTaxCodesService do
  subject(:result) { described_class.call(customer:, eu_tax_code:, tax_codes:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:, country: "GB", tax_identification_number:) }
  let(:tax_identification_number) { nil }
  let(:eu_tax_code) { "lago_eu_tax_exempt" }
  let(:tax_codes) { nil }

  let(:custom_tax) { create(:tax, organization:, code: "uk_vat", rate: 20.0) }
  let(:exempt_tax) { create(:tax, organization:, code: "lago_eu_tax_exempt", rate: 0.0) }

  context "when the customer is exempted and has custom taxes" do
    before do
      create(:customer_applied_tax, customer:, tax: custom_tax)
      create(:customer_applied_tax, customer:, tax: exempt_tax)
    end

    it "keeps the custom taxes without the exemption" do
      expect(result.tax_codes).to eq(["uk_vat"])
    end

    context "when the customer has a tax identification number" do
      let(:tax_identification_number) { "GB123456789" }

      it "applies the exemption only" do
        expect(result.tax_codes).to eq(["lago_eu_tax_exempt"])
      end
    end

    context "when the EU tax code is not the exemption" do
      let(:eu_tax_code) { "lago_eu_de_standard" }

      it "applies the EU tax code only" do
        expect(result.tax_codes).to eq(["lago_eu_de_standard"])
      end
    end
  end

  context "when the customer is exempted without custom taxes" do
    before { create(:customer_applied_tax, customer:, tax: exempt_tax) }

    it "applies the exemption" do
      expect(result.tax_codes).to eq(["lago_eu_tax_exempt"])
    end
  end

  context "when tax codes are given" do
    let(:tax_codes) { ["uk_vat"] }

    it "keeps the given custom taxes without the exemption" do
      expect(result.tax_codes).to eq(["uk_vat"])
    end

    context "when the given tax codes include the exemption" do
      let(:tax_codes) { %w[lago_eu_tax_exempt uk_vat] }

      it "keeps the given custom taxes without the exemption" do
        expect(result.tax_codes).to eq(["uk_vat"])
      end
    end

    context "when the given tax codes are empty" do
      let(:tax_codes) { [] }

      it "applies the exemption" do
        expect(result.tax_codes).to eq(["lago_eu_tax_exempt"])
      end
    end

    context "when the customer has a tax identification number" do
      let(:tax_identification_number) { "GB123456789" }

      it "adds the EU tax code to the given tax codes" do
        expect(result.tax_codes).to eq(%w[uk_vat lago_eu_tax_exempt])
      end
    end
  end
end
