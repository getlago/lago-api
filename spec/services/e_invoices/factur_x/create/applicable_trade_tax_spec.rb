# frozen_string_literal: true

require "rails_helper"

RSpec.describe EInvoices::FacturX::Create::ApplicableTradeTax, type: :service do
  subject do
    xml_document(:factur_x) do |xml|
      described_class.call(xml:, invoice:, applied_tax:)
    end
  end

  let(:invoice) { create(:invoice) }
  let(:applied_tax) { create(:invoice_applied_tax, invoice:, tax_rate: 20.00, fees_amount_cents: 1000) }

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

    it "has the tax category code" do
      expect(subject).to contains_xml_node("#{root}/ram:CategoryCode").with_value("S")
    end

    it "has the tax rate applicable percent" do
      expect(subject).to contains_xml_node("#{root}/ram:RateApplicablePercent").with_value("20.00")
    end
  end
end
