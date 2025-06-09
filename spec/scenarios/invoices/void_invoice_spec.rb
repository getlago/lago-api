# frozen_string_literal: true

require "rails_helper"

describe "Void Invoice Scenarios", :scenarios, type: :request do
  let(:organization) { create(:organization, webhook_url: nil) }
  let(:tax) { create(:tax, :applied_to_billing_entity, organization:, rate: 20) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:, amount_cents: 1000, pay_in_advance: true) }
  around { |test| lago_premium!(&test) }

  before do
    tax
    stub_pdf_generation
  end

  context "when voiding a basic invoice" do
    it "marks the invoice as voided" do
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
      invoice = subscription.invoices.first
      expect(invoice).to be_present
      expect(invoice).to be_finalized

      travel_to(DateTime.new(2023, 1, 5)) do
        void_invoice(invoice, { generate_credit_note: true , credit_amount: 1200, refund_amount: 0 })
      end

      invoice.reload
      expect(invoice).to be_voided
      expect(invoice.voided_at).to be_present

      credit_note = invoice.credit_notes.first
      expect(credit_note).to be_present
      expect(credit_note.credit_amount_cents).to eq(1200)
      expect(credit_note.refund_amount_cents).to eq(0)
      expect(credit_note.total_amount_cents).to eq(1200)
    end
  end
end
