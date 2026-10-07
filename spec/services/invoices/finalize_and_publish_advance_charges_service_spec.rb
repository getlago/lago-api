# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::FinalizeAndPublishAdvanceChargesService do
  describe ".call" do
    subject(:result) { described_class.call(invoice:) }

    let(:organization) { create(:organization) }
    let(:customer) { create(:customer, organization:) }
    let(:invoice) do
      create(:invoice, organization:, customer:, invoice_type:,
        status: invoice_status, total_amount_cents: 600)
    end
    let(:invoice_type) { :advance_charges }
    let(:invoice_status) { :generating }
    let(:sync_invoice) { true }
    let(:sync_hubspot_invoice) { true }

    before do
      allow(invoice).to receive(:should_sync_invoice?).and_return(sync_invoice)
      allow(invoice).to receive(:should_sync_hubspot_invoice?).and_return(sync_hubspot_invoice)
    end

    it "finalizes the invoice and enqueues its payment and integrations" do
      expect(result).to be_success
      expect(invoice.reload).to be_finalized
      expect(Payments::ManualCreateJob).to have_been_enqueued.once.with(
        organization:,
        params: {
          invoice_id: invoice.id,
          amount_cents: invoice.total_amount_cents,
          reference: I18n.t("invoice.charges_paid_in_advance"),
          created_at: invoice.created_at
        }
      )
      expect(Integrations::Aggregator::Invoices::CreateJob).to have_been_enqueued.with(invoice:)
      expect(Integrations::Aggregator::Invoices::Hubspot::CreateJob).to have_been_enqueued.with(invoice:)
    end

    context "without enabled integrations" do
      let(:sync_invoice) { false }
      let(:sync_hubspot_invoice) { false }

      it "does not enqueue invoice integrations" do
        expect(result).to be_success
        expect(Integrations::Aggregator::Invoices::CreateJob).not_to have_been_enqueued
        expect(Integrations::Aggregator::Invoices::Hubspot::CreateJob).not_to have_been_enqueued
      end
    end

    context "when the invoice closes during finalization" do
      let(:customer) { create(:customer, organization:, finalize_zero_amount_invoice: "skip") }
      let(:invoice) do
        create(:invoice, organization:, customer:, invoice_type: :advance_charges,
          status: :generating, total_amount_cents: 0, fees_amount_cents: 0)
      end

      it "does not publish or record a payment" do
        expect(result).to be_success
        expect(invoice.reload).to be_closed
        expect(SendWebhookJob).not_to have_been_enqueued.with("invoice.created", invoice)
        expect(Payments::ManualCreateJob).not_to have_been_enqueued
        expect(Invoices::GenerateDocumentsJob).not_to have_been_enqueued
        expect(Integrations::Aggregator::Invoices::CreateJob).not_to have_been_enqueued
        expect(Integrations::Aggregator::Invoices::Hubspot::CreateJob).not_to have_been_enqueued
      end
    end

    context "when the invoice is already finalized" do
      let(:invoice_status) { :finalized }

      it "publishes without repeating finalization" do
        expect(result).to be_success
        expect(Payments::ManualCreateJob).to have_been_enqueued.once
        expect(SendWebhookJob).to have_been_enqueued.with("invoice.created", invoice)
      end
    end

    context "when the invoice is not an advance charges invoice" do
      let(:invoice_type) { :subscription }

      before do
        allow(Invoices::TransitionToFinalStatusService).to receive(:call!).and_call_original
      end

      it "does not finalize or publish the invoice" do
        expect(result).to be_success
        expect(invoice.reload).to be_generating
        expect(Invoices::TransitionToFinalStatusService).not_to have_received(:call!)
        expect(SendWebhookJob).not_to have_been_enqueued.with("invoice.created", invoice)
        expect(Payments::ManualCreateJob).not_to have_been_enqueued
        expect(Invoices::GenerateDocumentsJob).not_to have_been_enqueued
      end
    end
  end
end
