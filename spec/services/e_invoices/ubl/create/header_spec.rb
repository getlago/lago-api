# frozen_string_literal: true

require "rails_helper"

RSpec.describe EInvoices::Ubl::Create::Header, type: :service do
  subject do
    xml_document(:ubl) do |xml|
      described_class.call(xml:, invoice:)
    end
  end

  let(:invoice) { create(:invoice, issuing_date: issuing_date.to_date, invoice_type:, currency:) }
  let(:invoice_type) { :subscription }
  let(:issuing_date) { "2025-03-16" }
  let(:currency) { "USD" }

  before { invoice }

  describe ".call" do
    it { is_expected.not_to be_nil }

    it "contains section name as comment" do
      expect(subject).to contains_xml_comment("Invoice Header Information")
    end

    context "with invoice" do
      it "expects to have the invoice number" do
        expect(subject).to contains_xml_node("//cbc:ID").with_value(invoice.number)
      end

      it "expects to have invoice issuing date" do
        expect(subject).to contains_xml_node("//cbc:IssueDate").with_value(issuing_date)
      end

      context "when InvoiceTypeCode" do
        let(:type_code_xpath) { "//cbc:InvoiceTypeCode" }

        it "expects to have a type code" do
          expect(subject).to contains_xml_node(type_code_xpath).with_value(380)
        end

        context "with credit invoice" do
          let(:invoice_type) { :credit }

          it "expects to have a type code" do
            expect(subject).to contains_xml_node(type_code_xpath).with_value(386)
          end
        end

        context "with self billed invoice" do
          before { invoice.update(self_billed: true) }

          it "expects to have a type code" do
            expect(subject).to contains_xml_node(type_code_xpath).with_value(389)
          end
        end
      end

      it "expects to have currency" do
        expect(subject).to contains_xml_node("//cbc:DocumentCurrencyCode")
          .with_value(invoice.currency)
      end
    end
  end
end
