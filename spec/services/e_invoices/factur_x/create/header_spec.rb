# frozen_string_literal: true

require "rails_helper"

RSpec.describe EInvoices::FacturX::Create::Header, type: :service do
  subject do
    xml_document(:factur_x) do |xml|
      described_class.call(xml:, invoice:)
    end
  end

  let(:invoice) { create(:invoice, issuing_date: issuing_date.to_date, invoice_type:) }
  let(:invoice_type) { :subscription }
  let(:issuing_date) { "20250316" }

  before { invoice }

  describe ".call" do
    it { is_expected.not_to be_nil }

    it "contains section name as comment" do
      expect(subject).to contains_xml_comment("Exchange Document Header")
    end

    context "with invoice" do
      let(:root) { "//rsm:ExchangedDocument" }

      it "expects to have the invoice number" do
        expect(subject).to contains_xml_node("#{root}/ram:ID").with_value(invoice.number)
      end

      context "when TypeCode" do
        it "expects to have a type code" do
          expect(subject).to contains_xml_node("#{root}/ram:TypeCode").with_value(380)
        end

        context "with credit invoice" do
          let(:invoice_type) { :credit }

          it "expects to have a type code" do
            expect(subject).to contains_xml_node("#{root}/ram:TypeCode").with_value(386)
          end
        end

        context "with self billed invoice" do
          before { invoice.update(self_billed: true) }

          it "expects to have a type code" do
            expect(subject).to contains_xml_node("#{root}/ram:TypeCode").with_value(389)
          end
        end
      end

      it "expects to have invoice issuing date" do
        expect(subject).to contains_xml_node("#{root}/ram:IssueDateTime/udt:DateTimeString")
          .with_value(issuing_date)
          .with_attribute("format", 102)
      end

      it "expects to have a included note" do
        expect(subject).to contains_xml_node("#{root}/ram:IncludedNote/ram:Content")
          .with_value("Invoice ID: #{invoice.id}")
      end
    end
  end
end
