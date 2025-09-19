# frozen_string_literal: true

require "rails_helper"

RSpec.describe EInvoices::Ubl::Create::PaymentTerms, type: :service do
  subject do
    xml_document(:ubl) do |xml|
      described_class.call(xml:, invoice:)
    end
  end

  let(:invoice) { create(:invoice, net_payment_term: 1) }

  let(:root) { "//cac:PaymentTerms" }

  describe ".call" do
    it { is_expected.not_to be_nil }

    it "contains section name as comment" do
      expect(subject).to contains_xml_comment("Payment Terms")
    end

    it "have Note with payment term days" do
      expect(subject).to contains_xml_node("#{root}/cbc:Note").with_value("Payment term 1 days")
    end

    context "when credit notes and prepaid credits" do
      before do
        invoice.update(
          credit_notes_amount_cents: 10_00,
          prepaid_credit_amount_cents: 11_86
        )
      end

      it "has the Note" do
        expect(subject).to contains_xml_node("#{root}/cbc:Note").with_value(
          "Payment term 1 days, Prepaid credits of EUR 11.86 applied, and Credit notes of EUR 10.00 applied"
        )
      end
    end
  end
end
