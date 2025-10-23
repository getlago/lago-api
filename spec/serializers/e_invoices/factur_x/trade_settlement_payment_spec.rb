# frozen_string_literal: true

require "rails_helper"

RSpec.describe EInvoices::FacturX::TradeSettlementPayment do
  subject do
    xml_document(:factur_x) do |xml|
      described_class.serialize(xml:, resource:, type:, amount:)
    end
  end

  let(:resource) { create(:invoice, currency: "USD") }
  let(:type) { described_class::STANDARD_PAYMENT }
  let(:amount) { Money.new(1000) }

  let(:root) { "//ram:SpecifiedTradeSettlementPaymentMeans" }

  describe ".serialize" do
    it { is_expected.not_to be_nil }

    context "when STANDARD_PAYMENT" do
      let(:type) { described_class::STANDARD_PAYMENT }

      it "contains section name as comment" do
        expect(subject).to contains_xml_comment("Payment Means: Standard payment")
      end

      it "have the payment code and information" do
        expect(subject).to contains_xml_node("#{root}/ram:TypeCode").with_value(type)
        expect(subject).to contains_xml_node("#{root}/ram:Information").with_value("Standard payment")
      end
    end

    context "when PREPAID_PAYMENT" do
      let(:type) { described_class::PREPAID_PAYMENT }

      it "contains section name as comment" do
        expect(subject).to contains_xml_comment("Payment Means: Prepaid credits")
      end

      it "have the payment code and information" do
        expect(subject).to contains_xml_node("#{root}/ram:TypeCode").with_value(type)
        expect(subject).to contains_xml_node("#{root}/ram:Information").with_value("Prepaid credits of USD 10.00 applied")
      end
    end

    context "when CREDIT_NOTE_PAYMENT" do
      let(:type) { described_class::CREDIT_NOTE_PAYMENT }

      it "contains section name as comment" do
        expect(subject).to contains_xml_comment("Payment Means: Credit notes")
      end

      it "have the payment code and information" do
        expect(subject).to contains_xml_node("#{root}/ram:TypeCode").with_value(type)
        expect(subject).to contains_xml_node("#{root}/ram:Information").with_value("Credit notes of USD 10.00 applied")
      end
    end
  end
end
