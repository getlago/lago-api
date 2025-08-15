# frozen_string_literal: true

require "rails_helper"

RSpec.describe EInvoices::Ubl::Create::PaymentMeans, type: :service do
  subject do
    xml_document(:ubl) do |xml|
      described_class.call(xml:, invoice:, type:, amount:)
    end
  end

  let(:invoice) { create(:invoice, currency: "USD") }
  let(:type) { described_class::STANDARD }
  let(:amount) { Money.new(1000) }

  let(:root) { "//cac:PaymentMeans" }

  describe ".call" do
    it { is_expected.not_to be_nil }

    context "when STANDARD" do
      let(:type) { described_class::STANDARD }

      it "contains section name as comment" do
        expect(subject).to contains_xml_comment("Payment Means: Standard payment")
      end

      it "have the payment code and information" do
        expect(subject).to contains_xml_node("#{root}/cbc:PaymentMeansCode").with_value(type)
        expect(subject).to contains_xml_node("#{root}/cbc:PaymentID").with_value("Standard payment")
      end
    end

    context "when PREPAID" do
      let(:type) { described_class::PREPAID }

      it "contains section name as comment" do
        expect(subject).to contains_xml_comment("Payment Means: Prepaid credits")
      end

      it "have the payment code and information" do
        expect(subject).to contains_xml_node("#{root}/cbc:PaymentMeansCode").with_value(type)
        expect(subject).to contains_xml_node("#{root}/cbc:PaymentID").with_value("Prepaid credits of USD 10.00 applied")
      end
    end

    context "when CREDIT_NOTE" do
      let(:type) { described_class::CREDIT_NOTE }

      it "contains section name as comment" do
        expect(subject).to contains_xml_comment("Payment Means: Credit notes")
      end

      it "have the payment code and information" do
        expect(subject).to contains_xml_node("#{root}/cbc:PaymentMeansCode").with_value(type)
        expect(subject).to contains_xml_node("#{root}/cbc:PaymentID").with_value("Credit notes of USD 10.00 applied")
      end
    end
  end
end
