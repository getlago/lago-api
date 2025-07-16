# frozen_string_literal: true

require "rails_helper"

RSpec.describe CreditNotes::CreateFromTermination, type: :service do
  subject(:create_service) { described_class.new(subscription:, context:) }

  let(:started_at) { Time.zone.parse("2022-09-01 10:00") }
  let(:subscription_at) { Time.zone.parse("2022-09-01 10:00") }
  let(:terminated_at) { Time.zone.parse("2022-10-15 10:00") }

  let(:customer) { create(:customer, **(customer_timezone ? {timezone: customer_timezone} : {})) }
  let(:customer_timezone) { nil }
  let(:organization) { customer.organization }
  let(:context) { nil }

  let(:subscription) do
    create(
      :subscription,
      customer:,
      plan:,
      status: :terminated,
      subscription_at:,
      started_at:,
      terminated_at:,
      billing_time: :calendar
    )
  end
  let(:plan) do
    create(
      :plan,
      :pay_in_advance,
      organization:,
      amount_cents: plan_amount_cents,
      **(trial_period ? {trial_period:} : {})
    )
  end
  let(:plan_amount_cents) { 31_00 }
  let(:trial_period) { nil }
  let(:tax) { create(:tax, organization:, rate: tax_rate) }
  let(:tax_rate) { 20 }
  let(:coupon_amount) { 0 }

  let(:fee_and_invoice) { generate_invoice_and_fee(plan_amount_cents) }
  let(:invoice) { fee_and_invoice[:invoice] }
  let(:subscription_fee) { fee_and_invoice[:subscription_fee] }
  let(:invoice_applied_tax) { fee_and_invoice[:invoice_applied_tax] }

  before { fee_and_invoice }

  def generate_invoice_and_fee(amount_cents, coupons_amount_cents: coupon_amount, at: started_at, plan_amount_cents: nil)
    taxes_amount_cents = ((amount_cents - coupons_amount_cents) * tax.rate / 100).round
    invoice = create(
      :invoice,
      organization:,
      customer:,
      currency: "EUR",
      coupons_amount_cents:,
      fees_amount_cents: amount_cents,
      total_amount_cents: amount_cents + taxes_amount_cents,
      created_at: at
    )
    subscription_fee = create(
      :fee,
      subscription:,
      invoice:,
      amount_cents:,
      taxes_amount_cents:,
      invoiceable_type: "Subscription",
      invoiceable_id: subscription.id,
      precise_coupons_amount_cents: coupons_amount_cents,
      taxes_rate: tax.rate,
      created_at: at,
      **(plan_amount_cents ? {amount_details: {plan_amount_cents:}} : {})
    )
    create(:fee_applied_tax, tax:, fee: subscription_fee, amount_cents: taxes_amount_cents)
    invoice_applied_tax = create(:invoice_applied_tax, invoice:, tax:, tax_rate: tax.rate, amount_cents: taxes_amount_cents)

    {
      subscription_fee:,
      invoice:,
      invoice_applied_tax:
    }
  end

  def expect_credit_note_to_be_properly_defined(credit_note, precise_item_amount_cents:, total_amount_cents:, tax_amount_cents:, fee: subscription_fee)
    expect(credit_note).to be_available
    expect(credit_note).to be_order_change

    expect(credit_note.total_amount_cents).to eq(total_amount_cents)
    expect(credit_note.total_amount_currency).to eq("EUR")
    expect(credit_note.credit_amount_cents).to eq(total_amount_cents)
    expect(credit_note.credit_amount_currency).to eq("EUR")
    expect(credit_note.refund_amount_cents).to eq(0)
    expect(credit_note.refund_amount_currency).to eq("EUR")
    expect(credit_note.taxes_amount_cents).to eq(tax_amount_cents)
    expect(credit_note.balance_amount_cents).to eq(total_amount_cents)
    expect(credit_note.balance_amount_currency).to eq("EUR")
    expect(credit_note.applied_taxes.length).to eq(1)
    expect(credit_note.applied_taxes.first.tax_code).to eq(invoice_applied_tax.tax_code)

    expect(credit_note.items.size).to eq(1)

    credit_note_item = credit_note.items.sole
    expect(credit_note_item.fee).to eq(fee)
    expect(credit_note_item.organization).to eq(organization)
    expect(credit_note_item.amount_cents).to eq(precise_item_amount_cents.round)
    expect(credit_note_item.precise_amount_cents).to eq(precise_item_amount_cents)
    expect(credit_note_item.amount_currency).to eq("EUR")
  end

  describe "#call" do
    it "creates a credit note" do
      result = create_service.call

      expect(result).to be_success

      credit_note = result.credit_note

      # 16 days of unused subscription fee
      # 16 * 1 euro per day + 20% tax = 19.2
      expect_credit_note_to_be_properly_defined(credit_note, total_amount_cents: 19_20, precise_item_amount_cents: 16_00, tax_amount_cents: 3_20)
    end

    context "with amount details attached to the fee" do
      let(:fee_and_invoice) { generate_invoice_and_fee(62_00, plan_amount_cents: 62_00) }

      it "creates a credit note based on the amount details" do
        result = create_service.call

        expect(result).to be_success

        credit_note = result.credit_note

        # 16 days of unused subscription fee
        # 16 * 2 euro per day + 20% tax = 38.4
        expect_credit_note_to_be_properly_defined(credit_note, total_amount_cents: 38_40, precise_item_amount_cents: 32_00, tax_amount_cents: 6_40)
      end
    end

    context "when invoice is voided" do
      before { invoice.void! }

      it "does not create a credit note" do
        expect { create_service.call }.not_to change(CreditNote, :count)
      end
    end

    context "when fee amount is zero" do
      let(:plan_amount_cents) { 0 }

      it "does not create a credit note" do
        expect { create_service.call }.not_to change(CreditNote, :count)
      end
    end

    context "when multiple fees" do
      let(:fee_and_invoice_2) do
        generate_invoice_and_fee(62_00, at: Time.zone.parse("2022-10-01 10:00"), plan_amount_cents: 62_00)
      end
      let(:invoice_2) { fee_and_invoice_2[:invoice] }
      let(:subscription_fee_2) { fee_and_invoice_2[:subscription_fee] }

      before { fee_and_invoice_2 }

      it "takes the last fee as reference" do
        result = create_service.call

        expect(result).to be_success

        credit_note = result.credit_note

        # 16 days of unused subscription fee
        # 16 * 2 euro per day + 20% tax = 38.4
        expect_credit_note_to_be_properly_defined(credit_note, total_amount_cents: 38_40, precise_item_amount_cents: 32_00, tax_amount_cents: 6_40, fee: subscription_fee_2)
      end
    end

    context "when existing credit notes on the fee" do
      let(:credit_note) do
        create(
          :credit_note,
          customer: subscription.customer,
          invoice: subscription_fee.invoice,
          credit_amount_cents: 10_00,
          taxes_amount_cents: 2_00
        )
      end
      let(:credit_note_item) do
        create(:credit_note_item, credit_note:, fee: subscription_fee, amount_cents: 10_00, precise_amount_cents: 10_00)
      end

      before { credit_note_item }

      it "takes the remaining creditable amount" do
        result = create_service.call

        expect(result).to be_success

        credit_note = result.credit_note

        # 16 days of unused subscription fee
        # 16 * 1 euro per day - 10 euro already credited + 20% tax = 7.2
        expect_credit_note_to_be_properly_defined(credit_note, total_amount_cents: 7_20, precise_item_amount_cents: 6_00, tax_amount_cents: 1_20)
      end
    end

    context "when plan has trial period ending after terminated_at" do
      let(:trial_period) { 46 }

      it "excludes the trial from the credit amount" do
        result = create_service.call

        expect(result).to be_success

        credit_note = result.credit_note

        # 15 days of unused subscription fee
        # 15 * 1 euro per day + 20% tax = 18
        expect_credit_note_to_be_properly_defined(credit_note, total_amount_cents: 18_00, precise_item_amount_cents: 15_00, tax_amount_cents: 3_00)
      end

      context "when trial ends after the end of the billing period" do
        let(:trial_period) { 120 }

        it "does not creates a credit note" do
          expect { create_service.call }.not_to change(CreditNote, :count)
        end
      end
    end

    context "when plan has been upgraded" do
      it "calculates credit note correctly" do
        result = described_class.new(subscription:, upgrade: true).call

        expect(result).to be_success

        credit_note = result.credit_note

        expect_credit_note_to_be_properly_defined(credit_note, total_amount_cents: 20_40, precise_item_amount_cents: 17_00, tax_amount_cents: 3_40)
      end
    end

    context "with a different timezone" do
      let(:started_at) { Time.zone.parse("2022-09-01 12:00") }
      let(:terminated_at) { Time.zone.parse("2022-10-15 01:00") }

      context "when timezone shift is UTC -" do
        let(:customer_timezone) { "America/Los_Angeles" }

        it "takes the timezone into account" do
          result = create_service.call

          expect(result).to be_success

          credit_note = result.credit_note

          # 17 days of unused subscription fee
          # 17 * 1 euro per day + 20% tax = 20.4
          expect_credit_note_to_be_properly_defined(credit_note, total_amount_cents: 20_40, precise_item_amount_cents: 17_00, tax_amount_cents: 3_40)
        end
      end

      context "when timezone shift is UTC +" do
        let(:customer_timezone) { "Europe/Paris" }

        it "takes the timezone into account" do
          result = create_service.call

          expect(result).to be_success

          credit_note = result.credit_note

          # 16 days of unused subscription fee
          # 16 * 1 euro per day + 20% tax = 19.2
          expect_credit_note_to_be_properly_defined(credit_note, total_amount_cents: 19_20, precise_item_amount_cents: 16_00, tax_amount_cents: 3_20)
        end
      end
    end

    context "with rounding at max precision" do
      let(:started_at) { Time.zone.parse("2023-01-30 10:00") }
      let(:subscription_at) { Time.zone.parse("2023-01-30 10:00") }
      let(:terminated_at) { Time.zone.parse("2023-03-14 10:00") }

      let(:subscription) do
        create(
          :subscription,
          plan:,
          customer:,
          status: :terminated,
          subscription_at:,
          started_at:,
          terminated_at:,
          billing_time: :anniversary
        )
      end

      let(:plan_amount_cents) { 99_9 }
      let(:tax_rate) { 0 }

      it "creates a credit note" do
        result = create_service.call

        expect(result).to be_success

        credit_note = result.credit_note

        # 15 days of unused subscription fee out of 30 days
        # 15 * (9.99/30) euro per day + 0% tax = 4.99
        expect_credit_note_to_be_properly_defined(credit_note, total_amount_cents: 4_99, precise_item_amount_cents: 4_99.49999, tax_amount_cents: 0)
      end
    end

    context "with a coupon applied to the invoice" do
      let(:coupon_amount) { 10_00 }

      it "takes the coupon into account" do
        result = create_service.call

        expect(result).to be_success

        credit_note = result.credit_note

        # 16 days of unused subscription fee
        # (16 * 1 euro per day - (10 euro coupon * 16/31)) + 20% tax = 13.01
        expect_credit_note_to_be_properly_defined(credit_note, total_amount_cents: 13_01, precise_item_amount_cents: 16_00, tax_amount_cents: 2_17)
      end
    end

    context "when 'preview' context provided" do
      let(:context) { :preview }

      it "builds a credit note" do
        result = create_service.call

        expect(result).to be_success

        credit_note = result.credit_note

        expect_credit_note_to_be_properly_defined(credit_note, total_amount_cents: 19_20, precise_item_amount_cents: 16_00, tax_amount_cents: 3_20)

        expect(credit_note).to be_a(CreditNote).and be_new_record
        expect(credit_note.items).to all be_new_record
      end

      it "does not persist any credit note" do
        expect { create_service.call }.not_to change(CreditNote, :count)
      end

      it "does not persist any credit note item" do
        expect { create_service.call }.not_to change(CreditNoteItem, :count)
      end
    end
  end
end
