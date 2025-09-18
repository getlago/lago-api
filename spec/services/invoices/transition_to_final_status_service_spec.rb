# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::TransitionToFinalStatusService do
  subject { described_class.new(invoice: invoice) }

  let(:organization) { create(:organization) }
  let(:billing_entity) { create(:billing_entity, organization:, finalize_zero_amount_invoice: billing_entity_setting) }
  let(:customer) { create(:customer, organization:, billing_entity:, finalize_zero_amount_invoice: customer_setting) }
  let(:billing_entity_setting) { "true" } # default value
  let(:customer_setting) { "inherit" }  # default value
  let(:fees_amount_cents) { 100 }
  let(:invoice) do
    create(
      :invoice,
      organization:,
      currency: "EUR",
      fees_amount_cents:,
      issuing_date: Time.zone.now.beginning_of_month,
      customer: customer
    )
  end

  describe "#call" do
    before { subject.call }

    context "when invoice fees_amount_cents is not zero" do
      it "finalizes the invoice" do
        expect(invoice.status).to eq("finalized")
      end

      context "with billing entity and customer settings defined to not finalize" do
        let(:organization_setting) { "false" }
        let(:customer_setting) { "skip" }

        it "finalizes the invoice" do
          expect(invoice.status).to eq("finalized")
        end
      end
    end

    context "when invoice fees_amount_cents is zero" do
      let(:fees_amount_cents) { 0 }

      context "with customer setting defined to finalize" do
        let(:customer_setting) { "finalize" }
        let(:organization_setting) { "false" }

        it "finalizes the invoice" do
          expect(invoice.status).to eq("finalized")
        end
      end

      context "with customer setting defined to skip" do
        let(:customer_setting) { "skip" }
        let(:organization_setting) { "true" }

        it "closes the invoice" do
          expect(invoice.status).to eq("closed")
        end
      end

      context "with customer setting defined to inherit" do
        let(:customer_setting) { "inherit" }

        context "with billing_entity setting to finalize" do
          let(:billing_entity_setting) { "true" }

          it "finalizes the invoice" do
            expect(invoice.status).to eq("finalized")
          end
        end

        context "with billing_entity setting to skip" do
          let(:billing_entity_setting) { "false" }

          it "closes the invoice" do
            expect(invoice.status).to eq("closed")
          end
        end
      end
    end
  end
end
