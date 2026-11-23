# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::RecordAdvanceChargesPaymentService do
  describe ".call" do
    subject(:result) { described_class.call(invoice:) }

    let_it_be(:organization) { create(:organization) }
    let_it_be(:customer) { create(:customer, organization:) }

    let(:invoice) do
      create(:invoice, organization:, customer:, invoice_type:, total_amount_cents:)
    end
    let(:invoice_type) { :advance_charges }
    let(:total_amount_cents) { 1_085 }

    it "enqueues a manual payment for the invoice total" do
      expect(result).to be_success
      expect(Payments::ManualCreateJob).to have_been_enqueued.once.with(
        organization:,
        params: {
          invoice_id: invoice.id,
          amount_cents: 1_085,
          reference: I18n.t("invoice.charges_paid_in_advance"),
          created_at: invoice.created_at
        }
      )
    end

    context "when the invoice total is zero" do
      let(:total_amount_cents) { 0 }

      it "does not enqueue a manual payment" do
        expect(result).to be_success
        expect(Payments::ManualCreateJob).not_to have_been_enqueued
      end
    end

    context "when the invoice is not an advance_charges invoice" do
      let(:invoice_type) { :subscription }

      it "does not enqueue a manual payment" do
        expect(result).to be_success
        expect(Payments::ManualCreateJob).not_to have_been_enqueued
      end
    end
  end
end
