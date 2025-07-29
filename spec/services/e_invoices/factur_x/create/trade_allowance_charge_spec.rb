# frozen_string_literal: true

require "rails_helper"

RSpec.describe EInvoices::FacturX::Create::TradeAllowanceCharge, type: :service do
  subject do
    xml_document(:factur_x) do |xml|
      described_class.call(xml:, invoice: nil, tax_rate:, amount:) do
      end
    end
  end

  let(:tax_rate) { 19.00 }
  let(:amount) { Money.new(1000) }

  let(:root) { "//ram:SpecifiedTradeAllowanceCharge" }

  describe ".call" do
    it { is_expected.not_to be_nil }

    it "contains section name as comment" do
      expect(subject).to contains_xml_comment("Allowance/Charge - Discount 19.00% portion")
    end

    it "is a discount" do
      expect(subject).to contains_xml_node("#{root}/ram:ChargeIndicator/udt:Indicator")
        .with_value(false)
    end

    it "has the ActualAmount" do
      expect(subject).to contains_xml_node("#{root}/ram:ActualAmount")
        .with_value("10.00")
    end

    it "has the Reason" do
      expect(subject).to contains_xml_node("#{root}/ram:Reason")
        .with_value("Discount 19.00% portion")
    end

    context "with CategoryTradeTax" do
      let(:trade_tax_root) { "#{root}/ram:CategoryTradeTax" }

      it "has the TypeCode" do
        expect(subject).to contains_xml_node("#{trade_tax_root}/ram:TypeCode")
          .with_value("VAT")
      end

      it "has the CategoryCode" do
        expect(subject).to contains_xml_node("#{trade_tax_root}/ram:CategoryCode")
          .with_value("S")
      end

      it "has the RateApplicablePercent" do
        expect(subject).to contains_xml_node("#{trade_tax_root}/ram:RateApplicablePercent")
          .with_value("19.00")
      end
    end
  end
end
