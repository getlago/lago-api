# frozen_string_literal: true

require "rails_helper"

RSpec.describe EInvoices::FacturX::Create::PaymentTerms, type: :service do
  subject do
    xml_document(:factur_x) do |xml|
      described_class.call(xml:, invoice:) do
      end
    end
  end

  let(:invoice) { create(:invoice, billing_entity:, payment_due_date: "20250316".to_date) }
  let(:billing_entity) { create(:billing_entity, net_payment_term: 0) }

  let(:root) { "//ram:SpecifiedTradePaymentTerms" }

  describe ".call" do
    it { is_expected.not_to be_nil }

    it "contains section name as comment" do
      expect(subject).to contains_xml_comment("Payment Terms")
    end

    it "have Description" do
      expect(subject).to contains_xml_node("#{root}/ram:Description")
        .with_value("Payment term 0 days")
    end

    it "have DueDate" do
      expect(subject).to contains_xml_node("#{root}/ram:DueDateDateTime/udt:DateTimeString")
        .with_value("20250316")
        .with_attribute("format", 102)
    end
  end
end
