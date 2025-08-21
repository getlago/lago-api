# frozen_string_literal: true

require "rails_helper"

RSpec.describe EInvoices::Ubl::Create::Delivery, type: :service do
  subject do
    xml_document(:ubl) do |xml|
      described_class.call(xml:, invoice:)
    end
  end

  let(:invoice_subscription1) { create(:invoice_subscription, :boundaries, invoice:, subscription: subscription1) }
  let(:invoice_subscription2) { create(:invoice_subscription, :boundaries, invoice:, subscription: subscription2) }
  let(:invoice) { create(:invoice, invoice_type:, created_at: "2025-03-16".to_date) }
  let(:invoice_type) { :subscription }
  let(:subscription1) { create(:subscription, started_at: "2025-03-16".to_date) }
  let(:subscription2) { create(:subscription, started_at: "2025-03-26".to_date) }
  let(:current_billing_period_started_at) { "2025-04-01" }
  let(:invoice_created_at) { "2025-03-16" }

  let(:root) { "//cac:Delivery" }

  before do
    invoice_subscription1
    invoice_subscription2
  end

  describe ".call" do
    it { is_expected.not_to be_nil }

    it "contains section name as comment" do
      expect(subject).to contains_xml_comment("Delivery Information")
    end

    context "when OccurrenceDateTime" do
      let(:xpath) { "#{root}/cbc:ActualDeliveryDate" }

      context "when subscription" do
        it "have the first date of subscription start" do
          travel_to(Time.zone.parse("2025-04-16")) do
            expect(subject).to contains_xml_node(xpath)
              .with_value(current_billing_period_started_at)
          end
        end
      end

      context "when one_off" do
        let(:invoice_type) { :one_off }

        it "have the creation date" do
          expect(subject).to contains_xml_node(xpath).with_value(invoice_created_at)
        end
      end

      context "when credit" do
        let(:invoice_type) { :credit }

        it "have the creation date" do
          expect(subject).to contains_xml_node(xpath).with_value(invoice_created_at)
        end
      end
    end
  end
end
