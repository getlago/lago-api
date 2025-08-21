# frozen_string_literal: true

require "rails_helper"

RSpec.describe EInvoices::Ubl::Create::MonetaryTotal, type: :service do
  subject do
    xml_document(:ubl) do |xml|
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

  let(:root) { "//cac:LegalMonetaryTotal" }

  describe ".call" do
    it { is_expected.not_to be_nil }

    it "contains section name as comment" do
      expect(subject).to contains_xml_comment("Legal Monetary Total")
    end

    it "have LineExtensionAmount" do
      expect(subject).to contains_xml_node("#{root}/cbc:LineExtensionAmount")
        .with_value("1000.00")
        .with_attribute("currencyID", "USD")
    end

    it "have ChargeTotalAmount and AllowanceTotalAmount" do
      expect(subject).to contains_xml_node("#{root}/cbc:ChargeTotalAmount")
        .with_value("0.00")
        .with_attribute("currencyID", "USD")
      expect(subject).to contains_xml_node("#{root}/cbc:AllowanceTotalAmount")
        .with_value("10.00")
        .with_attribute("currencyID", "USD")
    end

    it "have TaxExclusiveAmount" do
      expect(subject).to contains_xml_node("#{root}/cbc:TaxExclusiveAmount")
        .with_value("990.00")
        .with_attribute("currencyID", "USD")
    end

    it "have TaxInclusiveAmount" do
      expect(subject).to contains_xml_node("#{root}/cbc:TaxInclusiveAmount")
        .with_value("1188.84")
        .with_attribute("currencyID", "USD")
    end

    it "have PrepaidAmount" do
      expect(subject).to contains_xml_node("#{root}/cbc:PrepaidAmount")
        .with_value("21.86")
        .with_attribute("currencyID", "USD")
    end

    it "have PayableAmount" do
      expect(subject).to contains_xml_node("#{root}/cbc:PayableAmount")
        .with_value("1166.98")
        .with_attribute("currencyID", "USD")
    end
  end
end
