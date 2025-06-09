# frozen_string_literal: true

require "rails_helper"

describe "Void Invoice Scenarios", :scenarios, type: :request do
  let(:organization) { create(:organization, webhook_url: nil) }
  let(:tax) { create(:tax, :applied_to_billing_entity, organization:, rate: 20) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:, amount_cents: 1000, pay_in_advance: true) }

  before do
    tax
    stub_pdf_generation
  end

  context "when voiding a basic invoice" do
    it "marks the invoice as voided" do
      # Create a subscription
      travel_to(DateTime.new(2023, 1, 1)) do
        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: "sub_#{customer.external_id}",
            plan_code: plan.code
          }
        )
      end

      subscription = customer.subscriptions.first
      # An invoice should have been generated for the subscription
      invoice = subscription.invoices.first
      expect(invoice).to be_present
      expect(invoice).to be_finalized

      # Void the invoice
      travel_to(DateTime.new(2023, 1, 5)) do
        void_invoice(invoice, { generate_credit_note: true })
      end
      #
      # Verify the invoice is voided
      invoice.reload
      expect(invoice).to be_voided
      expect(invoice.voided_at).to be_present
      expect(invoice.payment_status).to eq("voided")
    end
  end

  xcontext "when voiding an invoice with full credit note generation" do
    it "voids the invoice and generates a full credit note" do
      # Create a subscription
      travel_to(DateTime.new(2023, 2, 1)) do
        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: "sub_full_credit_#{customer.external_id}",
            plan_code: plan.code
          }
        )
      end

      subscription = customer.subscriptions.first
      invoice = subscription.invoices.first
      expect(invoice).to be_present
      expect(invoice).to be_finalized

      # Add a payment to the invoice to test refund functionality
      travel_to(DateTime.new(2023, 2, 5)) do
        Payments::ManualCreateService.call(
          organization:,
          params: {invoice_id: invoice.id, amount_cents: 500, reference: "payment_ref_1"}
        )
      end

      # Void the invoice with credit note generation
      travel_to(DateTime.new(2023, 2, 10)) do
        void_invoice(
          invoice, 
          {
            generate_credit_note: true,
            credit_amount: invoice.creditable_amount_cents - 500, # Credit everything except what we'll refund
            refund_amount: 500 # Refund the payment we made
          }
        )
      end

      # Verify the invoice is voided
      invoice.reload
      expect(invoice).to be_voided
      expect(invoice.voided_at).to be_present

      # Verify a credit note is generated with the correct amounts
      expect(invoice.credit_notes.count).to eq(1)
      credit_note = invoice.credit_notes.first
      expect(credit_note).to be_present
      expect(credit_note.credit_amount_cents).to eq(invoice.creditable_amount_cents - 500)
      expect(credit_note.refund_amount_cents).to eq(500)
      expect(credit_note.total_amount_cents).to eq(invoice.total_amount_cents)
    end
  end

  xcontext "when voiding an invoice with partial credit note generation" do
    it "voids the invoice and generates partial credit notes" do
      # Create a subscription
      travel_to(DateTime.new(2023, 3, 1)) do
        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: "sub_partial_credit_#{customer.external_id}",
            plan_code: plan.code
          }
        )
      end

      subscription = customer.subscriptions.first
      invoice = subscription.invoices.first
      expect(invoice).to be_present
      expect(invoice).to be_finalized

      # Add a payment to the invoice
      travel_to(DateTime.new(2023, 3, 5)) do
        Payments::ManualCreateService.call(
          organization:,
          params: {invoice_id: invoice.id, amount_cents: 300, reference: "payment_ref_2"}
        )
      end

      # Calculate half of the creditable amount for partial credit
      half_creditable_amount = invoice.creditable_amount_cents / 2

      # Void the invoice with partial credit note generation
      travel_to(DateTime.new(2023, 3, 10)) do
        void_invoice(
          invoice, 
          {
            generate_credit_note: true,
            credit_amount: half_creditable_amount - 300, # Credit half minus what we'll refund
            refund_amount: 300 # Refund the payment we made
          }
        )
      end

      # Verify the invoice is voided
      invoice.reload
      expect(invoice).to be_voided
      expect(invoice.voided_at).to be_present

      # Verify credit notes are generated with the correct amounts
      expect(invoice.credit_notes.count).to eq(2)
      
      # First credit note should be for the specified partial amount
      first_credit_note = invoice.credit_notes.order(created_at: :asc).first
      expect(first_credit_note).to be_present
      expect(first_credit_note.credit_amount_cents).to eq(half_creditable_amount - 300)
      expect(first_credit_note.refund_amount_cents).to eq(300)
      expect(first_credit_note.total_amount_cents).to eq(half_creditable_amount)
      expect(first_credit_note).not_to be_voided

      # Second credit note should be for the remaining amount and should be voided
      second_credit_note = invoice.credit_notes.order(created_at: :asc).last
      expect(second_credit_note).to be_present
      expect(second_credit_note.total_amount_cents).to eq(invoice.creditable_amount_cents - half_creditable_amount)
      expect(second_credit_note).to be_voided
    end
  end
end
