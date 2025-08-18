# frozen_string_literal: true

require "rails_helper"

RSpec.describe EInvoices::Ubl::Create::Builder, type: :service do
  subject do
    xml_document(:ubl) do |xml|
      described_class.call(xml:, invoice:)
    end
  end

  let(:invoice_subscription) { create(:invoice_subscription, :boundaries, invoice:, subscription: subscription) }
  let(:subscription) { create(:subscription, started_at: "2025-03-16".to_date) }
  let(:invoice) { create(:invoice, total_amount_cents: 30_00, currency: "USD", coupons_amount_cents: 1000) }
  let(:fee) { create(:fee, invoice:, amount_cents: 10000, taxes_rate: 20.00) }
  let(:invoice_applied_tax) { create(:invoice_applied_tax, invoice:, fees_amount_cents: 40, tax_rate: 20.00) }

  before do
    fee
    invoice_subscription
    invoice_applied_tax
  end

  shared_examples "xml section" do |section|
    it "contains the section tag" do
      expect(subject).to contains_xml_node(section[:xpath])
    end

    it "contains section name before tag" do
      previous = subject.at_xpath(section[:xpath]).previous

      expect(previous).to be_comment
      expect(previous.text).to match(section[:name])
    end
  end

  payment_tag = "//cac:PaymentMeans"
  discount_tag = "//cac:AllowanceCharge"

  describe ".call" do
    it { is_expected.not_to be_nil }

    {
      ubl_info: {name: "UBL Version and Customization", xpath: "//cbc:UBLVersionID"},
      invoice_header: {name: "Invoice Header Information", xpath: "//cbc:ID"},
      invoice_seller: {name: "Supplier Party", xpath: "//cac:AccountingSupplierParty"},
      invoice_customer: {name: "Customer Party", xpath: "//cac:AccountingCustomerParty"},
      delivery: {name: "Delivery Information", xpath: "//cac:Delivery"},
      payment_and_credits: {name: "Payment Means:", xpath: "//cac:PaymentMeans"},
      payment_terms: {name: "Payment Terms", xpath: "//cac:PaymentTerms"},
      allowances_and_charges: {name: "Allowances and Charges", xpath: "//cac:AllowanceCharge"},
      tax_total: {name: "Tax Total Information", xpath: "//cac:TaxTotal"},
      monetary_total: {name: "Legal Monetary Total", xpath: "//cac:LegalMonetaryTotal"},
      line_items: {name: /Line Item \d{1,}:.*/, xpath: "//cac:InvoiceLine"}
    }.each do |reference, section|
      it_behaves_like "xml section", section
    end

    context "with Version and Customization" do
      it "have the document info" do
        expect(subject).to contains_xml_node("//cbc:UBLVersionID").with_value(2.1)
        expect(subject).to contains_xml_node("//cbc:CustomizationID").with_value("urn:cen.eu:en16931:2017")
      end
    end

    context "when payments and credits" do
      context "when something to pay" do
        it_behaves_like "xml section", {name: "Payment Means: Standard payment", xpath: "(#{payment_tag})[1]"}
      end

      context "with prepaid and credit note" do
        before do
          invoice.update(
            credit_notes_amount_cents: 10_00,
            prepaid_credit_amount_cents: 10_00
          )
        end

        it_behaves_like "xml section", {name: "Payment Means: Standard payment", xpath: "(#{payment_tag})[1]"}
        it_behaves_like "xml section", {name: "Payment Means: Prepaid credit", xpath: "(#{payment_tag})[2]"}
        it_behaves_like "xml section", {name: "Payment Means: Credit note", xpath: "(#{payment_tag})[3]"}
      end

      context "when nothing else to pay" do
        before do
          invoice.update(
            total_paid_amount_cents: invoice.total_due_amount_cents,
            credit_notes_amount_cents: invoice.total_due_amount_cents
          )
        end

        it_behaves_like "xml section", {name: "Payment Means: Credit note", xpath: "(#{payment_tag})[1]"}
      end
    end

    context "when discounts" do
      it_behaves_like "xml section", {name: "Allowances and Charges - Discount 20.00% portion", xpath: "(#{discount_tag})[1]"}

      context "with multiple fees" do
        let(:fee) { create(:fee, invoice:, amount_cents: 1551, taxes_rate: 19.00) }
        let(:fee2) { create(:fee, invoice:, amount_cents: 88449, taxes_rate: 20.00) }
        let(:fee3) { create(:fee, invoice:, amount_cents: 10000, taxes_rate: 21.00) }

        before {
          fee2
          fee3
        }

        context "with 19% tax discount" do
          xpath = "(#{discount_tag})[1]"

          it_behaves_like "xml section", {name: "Allowances and Charges - Discount 19.00% portion", xpath:}

          it "calculates the correct discount amount and tax" do
            expect(subject).to contains_xml_node("#{xpath}/cbc:Amount").with_value("0.16")
            expect(subject).to contains_xml_node("#{xpath}/cac:TaxCategory/cbc:Percent").with_value("19.00")
          end
        end

        context "with 20% tax discount" do
          xpath = "(#{discount_tag})[2]"

          it_behaves_like "xml section", {name: "Allowances and Charges - Discount 20.00% portion", xpath:}

          it "calculates the correct discount amount and tax" do
            expect(subject).to contains_xml_node("#{xpath}/cbc:Amount").with_value("8.84")
            expect(subject).to contains_xml_node("#{xpath}/cac:TaxCategory/cbc:Percent").with_value("20.00")
          end
        end

        context "with 21% tax discount" do
          xpath = "(#{discount_tag})[3]"

          it_behaves_like "xml section", {name: "Allowances and Charges - Discount 21.00% portion", xpath:}

          it "calculates the correct discount amount and tax" do
            expect(subject).to contains_xml_node("#{xpath}/cbc:Amount").with_value("1.00")
            expect(subject).to contains_xml_node("#{xpath}/cac:TaxCategory/cbc:Percent").with_value("21.00")
          end
        end
      end
    end

    context "with taxes" do
      taxes_xpath = "//cac:TaxTotal"

      it "has the sum of all taxes" do
        expect(subject).to contains_xml_node("#{taxes_xpath}/cbc:TaxAmount").with_value("2.00").with_attribute("currencyID", "USD")
      end

      context "with multiple taxes" do
        let(:invoice_applied_tax2) { create(:invoice_applied_tax, invoice:, tax_rate: 19.00) }

        before { invoice_applied_tax2 }

        it "has the sum of all taxes" do
          expect(subject).to contains_xml_node("#{taxes_xpath}/cbc:TaxAmount").with_value("4.00").with_attribute("currencyID", "USD")
        end

        it_behaves_like "xml section", {name: "Tax Information 20.00% VAT", xpath: "(#{taxes_xpath}/cac:TaxSubtotal)[1]"}
        it_behaves_like "xml section", {name: "Tax Information 19.00% VAT", xpath: "(#{taxes_xpath}/cac:TaxSubtotal)[2]"}
      end

      context "with zero taxes" do
        let(:invoice_applied_tax) { nil }

        it "has the sum of all taxes" do
          expect(subject).to contains_xml_node("#{taxes_xpath}/cbc:TaxAmount").with_value("0.00").with_attribute("currencyID", "USD")
        end
      end
    end
  end
end
