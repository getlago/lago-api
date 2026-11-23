# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::Payments::CollectService do
  describe ".call" do
    subject(:result) { described_class.call(invoice:, payment_method_params:) }

    let_it_be(:organization) { create(:organization) }
    let_it_be(:customer) { create(:customer, organization:, payment_provider: "stripe") }

    let(:invoice) do
      create(:invoice, organization:, customer:, invoice_type:, voided_invoice_id:, total_amount_cents: 1_200)
    end
    let(:invoice_type) { :subscription }
    let(:voided_invoice_id) { nil }
    let(:payment_method_params) { {payment_method_id: "pm_123"} }

    it "charges the payment provider" do
      expect(result).to be_success
      expect(Invoices::Payments::CreateJob).to have_been_enqueued
        .with(invoice:, payment_provider: :stripe, payment_method_params: {payment_method_id: "pm_123"})
      expect(Payments::ManualCreateJob).not_to have_been_enqueued
    end

    context "when the invoice is a regenerated advance_charges invoice" do
      let(:invoice_type) { :advance_charges }
      let(:voided_invoice_id) { create(:invoice, :voided, organization:, customer:, invoice_type:).id }

      it "records a manual payment instead of charging the payment provider" do
        expect(result).to be_success
        expect(Payments::ManualCreateJob).to have_been_enqueued.once.with(
          organization:,
          params: {
            invoice_id: invoice.id,
            amount_cents: 1_200,
            reference: I18n.t("invoice.charges_paid_in_advance"),
            created_at: invoice.created_at
          }
        )
        expect(Invoices::Payments::CreateJob).not_to have_been_enqueued
      end
    end
  end
end
