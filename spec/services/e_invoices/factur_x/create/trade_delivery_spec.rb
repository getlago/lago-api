# frozen_string_literal: true

require "rails_helper"

RSpec.describe EInvoices::FacturX::Create::TradeDelivery, type: :service do
  subject do
    xml_document(:factur_x) do |xml|
      described_class.call(xml:, invoice:)
    end
  end

  let(:invoice_subscription1) { create(:invoice_subscription, :boundaries, invoice:, subscription: subscription1) }
  let(:invoice_subscription2) { create(:invoice_subscription, :boundaries, invoice:, subscription: subscription2) }
  let(:invoice) { create(:invoice, invoice_type:, created_at: "2025-03-16".to_date) }
  let(:invoice_type) { :subscription }
  let(:subscription1) { create(:subscription, started_at: "2025-03-16".to_date) }
  let(:subscription2) { create(:subscription, started_at: "2025-03-26".to_date) }
  let(:current_billing_period_started_at) { "20250401" }
  let(:invoice_created_at) { "20250316" }

  let(:root) { "//ram:ApplicableHeaderTradeDelivery" }

  before do
    invoice_subscription1
    invoice_subscription2
  end

  describe ".call" do
    it { is_expected.not_to be_nil }

    it "contains section name as comment" do
      expect(subject).to contains_xml_comment("Applicable Header Trade Delivery")
    end

    context "when OccurrenceDateTime" do
      let(:xpath) { "#{root}/ram:ActualDeliverySupplyChainEvent/ram:OccurrenceDateTime/udt:DateTimeString" }

      context "when subscription" do
        it "have the first date of subscription start" do
          travel_to(Time.zone.parse("2025-04-16")) do
            expect(subject).to contains_xml_node(xpath)
              .with_value(current_billing_period_started_at)
              .with_attribute("format", 102)
          end
        end
      end

      context "when one_off" do
        let(:invoice_type) { :one_off }

        it "have the creation date" do
          expect(subject).to contains_xml_node(xpath).with_value(invoice_created_at).with_attribute("format", 102)
        end
      end
    end
  end
end
