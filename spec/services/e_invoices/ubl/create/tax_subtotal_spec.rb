# frozen_string_literal: true

require "rails_helper"

RSpec.describe EInvoices::Ubl::Create::TaxSubtotal, type: :service do
  subject do
    xml_document(:ubl) do |xml|
      described_class.call(xml:, invoice:, tax_rate:, amount:, tax:)
    end
  end

  let(:invoice) { create(:invoice, invoice_type:) }
  let(:amount) { 10 }
  let(:tax) { amount * (tax_rate / 100) }
  let(:tax_rate) { 20.00 }
  let(:invoice_type) { "subscription" }
  let(:root) { "//cac:TaxSubtotal" }

  describe ".call" do
    it { is_expected.not_to be_nil }

    it "contains section name as comment" do
      expect(subject).to contains_xml_comment("Tax Information 20.00% VAT")
    end

    it "have the tax calculated amount" do
      expect(subject).to contains_xml_node("#{root}/cbc:TaxAmount").with_value("2.00").with_attribute("currencyID", "EUR")
    end

    context "when TaxableAmount" do
      it "has the tax taxable amount" do
        expect(subject).to contains_xml_node("#{root}/cbc:TaxableAmount").with_value("10.00").with_attribute("currencyID", "EUR")
      end

      context "when taxes are zero" do
        let(:tax_rate) { 0.00 }

        it "zero the taxable amount" do
          expect(subject).to contains_xml_node("#{root}/cbc:TaxableAmount").with_value("10.00").with_attribute("currencyID", "EUR")
        end
      end
    end

    it "has the tax type scheme" do
      expect(subject).to contains_xml_node("#{root}/cac:TaxCategory/cac:TaxScheme/cbc:ID").with_value("VAT")
    end

    context "with tax_category" do
      let(:xpath) { "#{root}/cac:TaxCategory/cbc:ID" }

      it "has the S tax category code" do
        expect(subject).to contains_xml_node(xpath).with_value("S")
      end

      it "has the tax rate applicable percent" do
        expect(subject).to contains_xml_node("#{root}/cac:TaxCategory/cbc:Percent").with_value("20.00")
      end

      context "when taxes are zero" do
        let(:tax_rate) { 0.00 }

        it "has the Z category code" do
          expect(subject).to contains_xml_node(xpath).with_value("Z")
        end
      end

      context "when credit invoice" do
        let(:invoice_type) { "credit" }

        it "has the O category code" do
          expect(subject).to contains_xml_node(xpath).with_value("O")
        end

        it "has TaxExemptionReasonCode and TaxExemptionReason" do
          expect(subject).to contains_xml_node("#{root}/cac:TaxCategory/cbc:TaxExemptionReasonCode").with_value("VATEX-EU-O")
          expect(subject).to contains_xml_node("#{root}/cac:TaxCategory/cbc:TaxExemptionReason").with_value("Not subject to VAT")
        end

        it "does not has Percent" do
          expect(subject).not_to contains_xml_node("#{root}/cac:TaxCategory/cbc:Percent")
        end
      end
    end
  end
end
