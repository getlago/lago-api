# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::FinalizeContractInvoiceService do
  subject(:result) { described_class.call(invoice:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:invoice_type) { :contract }
  let(:invoice_status) { :generating }
  let(:total_amount_cents) { 600 }
  let(:invoice) do
    create(
      :invoice,
      organization:,
      customer:,
      invoice_type:,
      status: invoice_status,
      payment_status: :pending,
      total_amount_cents:,
      fees_amount_cents: total_amount_cents
    )
  end

  before do
    allow(Utils::ActivityLog).to receive(:produce)
    allow(Utils::SegmentTrack).to receive(:invoice_created)
    allow(Invoices::Payments::CreateService).to receive(:call_async)
  end

  it "finalizes the invoice and publishes it once" do
    expect(result).to be_success
    expect(result.invoice).to be_finalized
    expect(invoice.reload).to be_finalized
    expect(invoice.payment_status).to eq("pending")
    expect(SendWebhookJob).to have_been_enqueued.once.with("invoice.created", invoice)
    expect(Invoices::GenerateDocumentsJob).to have_been_enqueued.once.with(invoice:, notify: false)
    expect(Utils::ActivityLog).to have_received(:produce).once.with(invoice, "invoice.created")
    expect(Invoices::Payments::CreateService).to have_received(:call_async).once.with(invoice:)
    expect(Utils::SegmentTrack).to have_received(:invoice_created).once.with(invoice)
  end

  it "does not sync the invoice with integrations" do
    result

    expect(Integrations::Aggregator::Invoices::CreateJob).not_to have_been_enqueued
    expect(Integrations::Aggregator::Invoices::Hubspot::CreateJob).not_to have_been_enqueued
  end

  context "with a premium license", :premium do
    it "notifies the customer" do
      result

      expect(Invoices::GenerateDocumentsJob).to have_been_enqueued.once.with(invoice:, notify: true)
    end

    context "when the billing entity does not send the finalized email" do
      before { invoice.billing_entity.update!(email_settings: []) }

      it "does not notify the customer" do
        result

        expect(Invoices::GenerateDocumentsJob).to have_been_enqueued.once.with(invoice:, notify: false)
      end
    end
  end

  context "when the invoice is a draft" do
    let(:invoice_status) { :draft }

    it "finalizes and publishes the invoice" do
      expect(result).to be_success
      expect(invoice.reload).to be_finalized
      expect(SendWebhookJob).to have_been_enqueued.once.with("invoice.created", invoice)
    end
  end

  context "when the total amount is zero" do
    let(:total_amount_cents) { 0 }
    let(:customer) { create(:customer, organization:, finalize_zero_amount_invoice: "finalize") }

    it "finalizes the invoice as paid" do
      expect(result).to be_success
      expect(invoice.reload).to be_finalized
      expect(invoice.payment_status).to eq("succeeded")
      expect(SendWebhookJob).to have_been_enqueued.once.with("invoice.created", invoice)
    end
  end

  context "when the invoice closes during finalization" do
    let(:total_amount_cents) { 0 }
    let(:customer) { create(:customer, organization:, finalize_zero_amount_invoice: "skip") }

    it "publishes nothing" do
      expect(result).to be_success
      expect(invoice.reload).to be_closed
      expect(invoice.payment_status).to eq("succeeded")
      expect(SendWebhookJob).not_to have_been_enqueued
      expect(Invoices::GenerateDocumentsJob).not_to have_been_enqueued
      expect(Utils::ActivityLog).not_to have_received(:produce)
      expect(Invoices::Payments::CreateService).not_to have_received(:call_async)
      expect(Utils::SegmentTrack).not_to have_received(:invoice_created)
    end
  end

  context "when the invoice is already finalized" do
    let(:invoice_status) { :finalized }

    it "does not publish it again" do
      expect(result).to be_success
      expect(SendWebhookJob).not_to have_been_enqueued
      expect(Invoices::GenerateDocumentsJob).not_to have_been_enqueued
      expect(Utils::ActivityLog).not_to have_received(:produce)
      expect(Invoices::Payments::CreateService).not_to have_received(:call_async)
      expect(Utils::SegmentTrack).not_to have_received(:invoice_created)
    end
  end

  context "when the invoice is not a contract invoice" do
    let(:invoice_type) { :subscription }

    it "does not finalize or publish it" do
      expect(result).to be_success
      expect(invoice.reload).to be_generating
      expect(SendWebhookJob).not_to have_been_enqueued
      expect(Invoices::GenerateDocumentsJob).not_to have_been_enqueued
      expect(Utils::ActivityLog).not_to have_received(:produce)
    end
  end
end
