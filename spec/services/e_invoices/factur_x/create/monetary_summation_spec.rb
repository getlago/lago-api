# frozen_string_literal: true

require "rails_helper"

RSpec.describe EInvoices::FacturX::Create::MonetarySummation, type: :service do
  subject do
    xml_document(:factur_x) do |xml|
      described_class.call(xml:, invoice:) do
      end
    end
  end

  let(:invoice) do
    create(:invoice,
      fees_amount_cents: 100000,
      coupons_amount_cents: 1000,
      sub_total_excluding_taxes_amount_cents: 99000,
      taxes_amount_cents: 19884,
      currency: "USD",
      sub_total_including_taxes_amount_cents: 118884,
      prepaid_credit_amount_cents: 1186,
      credit_notes_amount_cents: 1000,
      total_paid_amount_cents: 2186,
      total_amount_cents: 118884)
  end

  let(:root) { "//ram:SpecifiedTradeSettlementHeaderMonetarySummation" }

  describe ".call" do
    it { is_expected.not_to be_nil }

    it "contains section name as comment" do
      expect(subject).to contains_xml_comment("Monetary Summation")
    end

    it "have LineTotalAmount" do
      expect(subject).to contains_xml_node("#{root}/ram:LineTotalAmount")
        .with_value("1000.00")
    end

    it "have ChargeTotalAmount and AllowanceTotalAmount" do
      expect(subject).to contains_xml_node("#{root}/ram:ChargeTotalAmount")
        .with_value("0.00")
      expect(subject).to contains_xml_node("#{root}/ram:AllowanceTotalAmount")
        .with_value("10.00")
    end

    it "have TaxBasisTotalAmount" do
      expect(subject).to contains_xml_node("#{root}/ram:TaxBasisTotalAmount")
        .with_value("990.00")
    end

    it "have TaxTotalAmount" do
      expect(subject).to contains_xml_node("#{root}/ram:TaxTotalAmount")
        .with_value("198.84")
        .with_attribute("currencyID", "USD")
    end

    it "have TotalPrepaidAmount" do
      expect(subject).to contains_xml_node("#{root}/ram:TotalPrepaidAmount")
        .with_value("21.86")
    end

    it "have DuePayableAmount" do
      expect(subject).to contains_xml_node("#{root}/ram:DuePayableAmount")
        .with_value("1166.98")
    end
  end
end
