# frozen_string_literal: true

require "rails_helper"

RSpec.describe CreditNotes::CreateFromProgressiveBillingInvoice do
  subject(:credit_service) { described_class.new(progressive_billing_invoice:, amount:, reason:) }

  let(:reason) { :other }
  let(:amount) { 0 }
  let(:invoice_type) { :progressive_billing }
  let(:customer) { create(:customer) }
  let(:organization) { customer.organization }
  let(:tax) { create(:tax, organization:, rate: 20) }

  let(:progressive_billing_invoice) do
    create(
      :invoice,
      customer:,
      organization:,
      currency: "EUR",
      fees_amount_cents: 120,
      total_amount_cents: 120,
      invoice_type:
    )
  end

  let(:fee1) do
    create(
      :fee,
      invoice: progressive_billing_invoice,
      amount_cents: 80,
      taxes_amount_cents: 16,
      taxes_rate: 20
    )
  end

  let(:fee2) do
    create(
      :fee,
      invoice: progressive_billing_invoice,
      amount_cents: 40,
      taxes_amount_cents: 8,
      taxes_rate: 20
    )
  end

  let(:fee1_applied_tax) { create(:fee_applied_tax, tax:, fee: fee1) }
  let(:fee2_applied_tax) { create(:fee_applied_tax, tax:, fee: fee2) }
  let(:invoice_applied_tax) { create(:invoice_applied_tax, invoice: progressive_billing_invoice, tax:) }

  before do
    progressive_billing_invoice
    fee1
    fee2
    fee1_applied_tax
    fee2_applied_tax
    invoice_applied_tax
  end

  describe "#call" do
    it "does nothing when amount is zero" do
      expect { credit_service.call }.not_to change(CreditNote, :count)
    end

    context "with amount greater than zero" do
      let(:amount) { 100 }

      context "when called with a subscription invoice" do
        let(:invoice_type) { :subscription }

        it "fails when the passed in invoice is not a progressive billing invoice" do
          result = credit_service.call
          expect(result).not_to be_success
        end
      end

      it "creates a credit note for all required fees" do
        result = credit_service.call
        credit_note = result.credit_note

        expect(credit_note.credit_amount_cents).to eq(120)
        expect(credit_note.items.size).to eq(2)

        credit_fee1 = credit_note.items.find { |i| i.fee == fee1 }
        expect(credit_fee1.amount_cents).to eq(80)
        credit_fee2 = credit_note.items.find { |i| i.fee == fee2 }
        expect(credit_fee2.amount_cents).to eq(20)
        expect(credit_note.applied_taxes.length).to eq(1)
        expect(credit_note.applied_taxes.first.tax_code).to eq(invoice_applied_tax.tax_code)
        expect(credit_note.applied_taxes.first.tax_id).to eq(tax.id)
      end

      context "when final credit amount becomes zero or negative after adjustments" do
        let(:amount) { 0.0005 }

        it "does not create a credit note" do
          result = credit_service.call

          expect(result).to be_success
          expect(result.credit_note).to be_nil
          expect(CreditNote.count).to eq(0)
        end
      end

      context "when all fees have been fully credited" do
        let(:amount) { 50 }
        let(:existing_credit_note) do
          create(
            :credit_note,
            invoice: progressive_billing_invoice,
            credit_amount_cents: 120,
            total_amount_cents: 120
          )
        end

        before do
          existing_credit_note
          create(:credit_note_item, credit_note: existing_credit_note, fee: fee1, amount_cents: 80)
          create(:credit_note_item, credit_note: existing_credit_note, fee: fee2, amount_cents: 40)
        end

        it "does not create a credit note" do
          result = credit_service.call

          expect(result).to be_success
          expect(result.credit_note).to be_nil
          expect(CreditNote.count).to eq(1)
        end
      end

      context "when coupon adjustments reduce the credit amount to zero" do
        let(:amount) { 10 }

        before do
          # Apply coupons to the fees on the progressive billing invoice
          # This simulates the production scenario where coupons have been applied
          # The coupon adjustment is calculated as: item.fee.precise_coupons_amount_cents * item_fee_rate
          # In this case, we're crediting 10 from fee1 (which has 80 amount_cents and 80 precise_coupons_amount_cents)
          # So the coupon adjustment will be: 80 * (10/80) = 10
          # This means: final_amount = 10 - 10 + taxes = taxes_only
          # With taxes at 20%, taxes on (10-10) = 0, so final amount = 0
          fee1.update!(precise_coupons_amount_cents: 80)
          fee2.update!(precise_coupons_amount_cents: 40)

          # Ensure the invoice supports coupons before VAT
          progressive_billing_invoice.update!(
            version_number: Invoice::COUPON_BEFORE_VAT_VERSION,
            coupons_amount_cents: 120,
            sub_total_excluding_taxes_amount_cents: 0
          )
        end

        it "does not create a credit note when coupon adjustment equals or exceeds the amount" do
          result = credit_service.call

          expect(result).to be_success
          expect(result.credit_note).to be_nil
          expect(CreditNote.count).to eq(0)
        end
      end
    end
  end
end
