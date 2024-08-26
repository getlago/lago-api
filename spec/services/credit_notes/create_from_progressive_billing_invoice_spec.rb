# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CreditNotes::CreateFromProgressiveBillingInvoice, type: :service do
  subject(:credit_service) { described_class.new(progressive_billing_invoice:, amount:, reason:) }

  let(:reason) { :other }
  let(:amount) { 0 }
  let(:invoice_type) { :progressive_billing }
  let(:customer) { create(:customer) }
  let(:organization) { customer.organization }

  let(:progressive_billing_invoice) do
    create(
      :invoice,
      customer:,
      organization:,
      currency: 'EUR',
      fees_amount_cents: 120,
      total_amount_cents: 120,
      invoice_type:
    )
  end

  let(:fee1) do
    create(
      :fee,
      invoice: progressive_billing_invoice,
      amount_cents: 80
    )
  end

  let(:fee2) do
    create(
      :fee,
      invoice: progressive_billing_invoice,
      amount_cents: 40
    )
  end

  before do
    progressive_billing_invoice
    fee1
    fee2
  end

  describe "#call" do
    it "does nothing when amount is zero" do
      expect { credit_service.call }.not_to change(CreditNote, :count)
    end

    context "with amount greater than zero" do
      let(:amount) { 100 }

      context 'when called with a subscription invoice' do
        let(:invoice_type) { :subscription }

        it "fails when the passed in invoice is not a progressive billing invoice" do
          result = credit_service.call
          expect(result).not_to be_success
        end
      end

      it "creates a credit note for all required fees" do
        result = credit_service.call
        credit_note = result.credit_note

        expect(credit_note.credit_amount_cents).to eq(amount)
        expect(credit_note.items.size).to eq(2)

        credit_fee1 = credit_note.items.find { |i| i.fee == fee1 }
        expect(credit_fee1.amount_cents).to eq(80)
        credit_fee2 = credit_note.items.find { |i| i.fee == fee2 }
        expect(credit_fee2.amount_cents).to eq(20)
      end
    end
  end
end
