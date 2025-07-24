# frozen_string_literal: true

require "rails_helper"

RSpec.describe EInvoice::FacturX::Create::Header, type: :service do
  subject do
    xml_document(:factur_x) do |xml|
      described_class.call(xml:, invoice:)
    end
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:invoice) { create(:invoice, customer:, organization:, issuing_date: issuing_date.to_date) }
  let(:issuing_date) { "20250316" }

  before { invoice }

  describe ".call" do
    it { is_expected.not_to be_nil }

    it "contains section name as comment" do
      expect(subject).to xml_document_have_comment("Exchange Document Header")
    end

    context "with invoice" do
      let(:root) { "//rsm:ExchangedDocument" }

      it "expects to have the invoice number" do
        expect(subject).to xml_document_have_node("#{root}/ram:ID", invoice.number)
      end

      it "expects to have a type code" do
        expect(subject).to xml_document_have_node("#{root}/ram:TypeCode", 380)
      end

      it "expects to have invoice issuing date" do
        expect(subject).to xml_document_have_node("#{root}/ram:IssueDateTime/udt:DateTimeString", issuing_date)
        expect(subject).to xml_node_have_attribute("#{root}/ram:IssueDateTime/udt:DateTimeString", "format", 102)
      end

      it "expects to have a included note" do
        expect(subject).to xml_document_have_node("#{root}/ram:IncludedNote/ram:Content", "Invoice ID: #{invoice.id}")
      end
    end
  end
end
