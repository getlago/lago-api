# frozen_string_literal: true

require "rails_helper"

RSpec.describe EInvoices::FacturX::Create::ApplicableTradeTax, type: :service do
  subject do
    xml_document(:factur_x) do |xml|
      described_class.call(xml:, invoice:, applied_tax:)
    end
  end

  let(:invoice) { create(:invoice, invoice_type:) }
  let(:applied_tax) { create(:invoice_applied_tax, invoice:, tax_rate:, fees_amount_cents: 1000) }
  let(:tax_rate) { 20.00 }
  let(:invoice_type) { "subscription" }
  let(:root) { "//ram:ApplicableTradeTax" }

  before do
    applied_tax
  end

  describe ".call" do
    it { is_expected.not_to be_nil }

    it "contains section name as comment" do
      expect(subject).to contains_xml_comment("Tax Information 20.00% VAT")
    end

    it "have the tax calculated amount" do
      expect(subject).to contains_xml_node("#{root}/ram:CalculatedAmount").with_value("2.00")
    end

    it "has the tax type code" do
      expect(subject).to contains_xml_node("#{root}/ram:TypeCode").with_value("VAT")
    end

    it "has the tax basis amount" do
      expect(subject).to contains_xml_node("#{root}/ram:BasisAmount").with_value("10.00")
    end

    context "with tax_category" do
      it "has the S tax category code" do
        expect(subject).to contains_xml_node("#{root}/ram:CategoryCode").with_value("S")
      end

      context "when taxes are zero" do
        let(:tax_rate) { 0.00 }

        it "has the Z category code" do
          expect(subject).to contains_xml_node("#{root}/ram:CategoryCode").with_value("Z")
        end
      end

      context "when credit invoice" do
        let(:invoice_type) { "credit" }

        it "has the O category code" do
          expect(subject).to contains_xml_node("#{root}/ram:CategoryCode").with_value("O")
        end
      end
    end

    context "when credit invoice" do
      let(:invoice_type) { "credit" }

      it "has ExemptionReasonCode" do
        expect(subject).to contains_xml_node("#{root}/ram:ExemptionReasonCode").with_value("VATEX-EU-O")
      end

      it "does not has RateApplicablePercent" do
        expect(subject).not_to contains_xml_node("#{root}/ram:RateApplicablePercent")
      end
    end

    it "has the tax rate applicable percent" do
      expect(subject).to contains_xml_node("#{root}/ram:RateApplicablePercent").with_value("20.00")
    end
  end
end
