# frozen_string_literal: true

require "rails_helper"

RSpec.describe EInvoices::FacturX::Create::TradeSettlement, type: :service do
  subject do
    xml_document(:factur_x) do |xml|
      described_class.call(xml:, invoice:) do
      end
    end
  end

  let(:invoice) { create(:invoice, currency: "EUR") }

  let(:root) { "//ram:ApplicableHeaderTradeSettlement" }

  describe ".call" do
    it { is_expected.not_to be_nil }

    it "contains section name as comment" do
      expect(subject).to contains_xml_comment("Applicable Header Trade Settlement")
    end

    it "have the invoice currency" do
      expect(subject).to contains_xml_node("#{root}/ram:InvoiceCurrencyCode")
        .with_value("EUR")
    end
  end
end
