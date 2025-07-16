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
      amount_cents: 31_00,
      **(trial_period ? {trial_period:} : {})
    )
  end
  let(:plan_amount_cents) { 31_00 }
  let(:trial_period) { nil }

  let(:subscription_fee) do
    create(
      :fee,
      subscription:,
      invoice:,
      amount_cents: 31_00,
      taxes_amount_cents: 6_00,
      invoiceable_type: "Subscription",
      invoiceable_id: subscription.id,
      taxes_rate: tax_rate
    )
  end

  let(:invoice) do
    create(
      :invoice,
      organization:,
      customer:,
      currency: "EUR",
      fees_amount_cents: 31_00,
      taxes_amount_cents: 6_00,
      total_amount_cents: 37_00
    )
  end

  let(:tax) { create(:tax, organization:, rate: tax_rate) }
  let(:tax_rate) { 20 }
  let(:fee_applied_tax) do
    amount_cents = subscription_fee.amount_cents.positive? ? (subscription_fee.taxes_amount_cents / subscription_fee.amount_cents) : 0
    create(:fee_applied_tax, tax:, tax_rate:, amount_cents: amount_cents, fee: subscription_fee)
  end
  let(:invoice_applied_tax) do
    amount_cents = invoice.fees_amount_cents.positive? ? (invoice.taxes_amount_cents / invoice.fees_amount_cents) : 0
    create(:invoice_applied_tax, invoice:, tax_rate:, tax:, amount_cents:)
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
    before do
      fee_applied_tax
      invoice_applied_tax
    end

    it "creates a credit note" do
      result = create_service.call

      expect(result).to be_success

      credit_note = result.credit_note

      expect_credit_note_to_be_properly_defined(credit_note, total_amount_cents: 19_20, precise_item_amount_cents: 16_00, tax_amount_cents: 3_20)
    end

    context "with amount details attached to the fee" do
      let(:subscription_fee) do
        create(
          :fee,
          subscription:,
          invoice:,
          amount_cents: 62_00,
          taxes_amount_cents: 12_00,
          invoiceable_type: "Subscription",
          invoiceable_id: subscription.id,
          taxes_rate: tax_rate,
          created_at: Time.zone.parse("2023-02-28 10:00"),
          amount_details: {"plan_amount_cents" => 62_00}
        )
      end
      let(:invoice) do
        create(
          :invoice,
          organization:,
          customer:,
          currency: "EUR",
          fees_amount_cents: 62_00,
          taxes_amount_cents: 12_00,
          total_amount_cents: 74_00
        )
      end

      it "creates a credit note based on the amount details" do
        travel_to(terminated_at) do
          result = create_service.call

          expect(result).to be_success

          credit_note = result.credit_note

          expect_credit_note_to_be_properly_defined(credit_note, total_amount_cents: 38_40, precise_item_amount_cents: 32_00, tax_amount_cents: 6_40)
        end
      end
    end

    context "when invoice is voided" do
      before { invoice.void! }

      it "does not create a credit note" do
        expect { create_service.call }.not_to change(CreditNote, :count)
      end
    end

    context "when fee amount is zero" do
      let(:subscription_fee) do
        create(
          :fee,
          subscription:,
          invoice:,
          amount_cents: 0,
          taxes_amount_cents: 0,
          invoiceable_type: "Subscription",
          invoiceable_id: subscription.id,
          taxes_rate: tax_rate
        )
      end

      it "does not create a credit note" do
        expect { create_service.call }.not_to change(CreditNote, :count)
      end
    end

    context "when multiple fees" do
      let(:invoice) do
        create(
          :invoice,
          organization:,
          customer:,
          currency: "EUR",
          fees_amount_cents: 31_00,
          taxes_amount_cents: 6_00,
          total_amount_cents: 37_00,
          created_at: Time.current - 2.months
        )
      end
      let(:subscription_fee) do
        create(
          :fee,
          subscription:,
          invoice:,
          amount_cents: 31_00,
          taxes_amount_cents: 6_00,
          invoiceable_type: "Subscription",
          invoiceable_id: subscription.id,
          taxes_rate: tax_rate,
          created_at: Time.current - 2.months
        )
      end

      let(:invoice_2) do
        create(
          :invoice,
          organization:,
          customer:,
          currency: "EUR",
          fees_amount_cents: 31_00,
          taxes_amount_cents: 6_00,
          total_amount_cents: 37_00,
          created_at: Time.current - 1.month
        )
      end
      let(:subscription_fee_2) do
        create(
          :fee,
          subscription:,
          invoice: invoice_2,
          amount_cents: 31_00,
          taxes_amount_cents: 6_00,
          invoiceable_type: "Subscription",
          invoiceable_id: subscription.id,
          taxes_rate: tax_rate,
          created_at: Time.current - 1.month
        )
      end
      let(:fee_applied_tax_2) do
        amount_cents = subscription_fee_2.amount_cents.positive? ? (subscription_fee_2.taxes_amount_cents / subscription_fee_2.amount_cents) : 0
        create(:fee_applied_tax, tax:, tax_rate:, amount_cents: amount_cents, fee: subscription_fee_2)
      end
      let(:invoice_applied_tax_2) do
        amount_cents = invoice_2.fees_amount_cents.positive? ? (invoice_2.taxes_amount_cents / invoice_2.fees_amount_cents) : 0
        create(:invoice_applied_tax, invoice: invoice_2, tax_rate:, tax:, amount_cents:)
      end

      before do
        fee_applied_tax_2
        invoice_applied_tax_2
      end

      it "takes the last fee as reference" do
        result = create_service.call

        expect(result).to be_success

        credit_note = result.credit_note

        expect_credit_note_to_be_properly_defined(credit_note, total_amount_cents: 19_20, precise_item_amount_cents: 16_00, tax_amount_cents: 3_20, fee: subscription_fee_2)
      end
    end

    context "when existing credit notes on the fee" do
      let(:credit_note) do
        create(
          :credit_note,
          customer: subscription.customer,
          invoice: subscription_fee.invoice,
          credit_amount_cents: 10_00
        )
      end

      let(:credit_note_item) do
        create(
          :credit_note_item,
          credit_note:,
          fee: subscription_fee,
          amount_cents: 10_00
        )
      end

      before { credit_note_item }

      it "takes the remaining creditable amount" do
        result = create_service.call

        expect(result).to be_success

        credit_note = result.credit_note

        expect_credit_note_to_be_properly_defined(credit_note, total_amount_cents: 7_20, precise_item_amount_cents: 6_00, tax_amount_cents: 1_20)
      end
    end

    context "when plan has trial period ending after terminated_at" do
      let(:trial_period) { 46 }

      it "excludes the trial from the credit amount" do
        result = create_service.call

        expect(result).to be_success

        credit_note = result.credit_note

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

          expect_credit_note_to_be_properly_defined(credit_note, total_amount_cents: 20_40, precise_item_amount_cents: 17_00, tax_amount_cents: 3_40)
        end
      end

      context "when timezone shift is UTC +" do
        let(:customer_timezone) { "Europe/Paris" }

        it "takes the timezone into account" do
          result = create_service.call

          expect(result).to be_success

          credit_note = result.credit_note

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

      let(:plan_amount_cents) { 9_99 }

      let(:invoice) do
        create(
          :invoice,
          customer:,
          currency: "EUR",
          fees_amount_cents: 9_99,
          taxes_amount_cents: 0,
          total_amount_cents: 9_99
        )
      end

      let(:subscription_fee) do
        create(
          :fee,
          subscription:,
          invoice:,
          amount_cents: 999,
          taxes_amount_cents: 0,
          invoiceable_type: "Subscription",
          invoiceable_id: subscription.id,
          taxes_rate: tax_rate,
          created_at: Time.zone.parse("2023-02-28 10:00"),
          amount_details: {"plan_amount_cents" => 9_99}
        )
      end
      let(:tax_rate) { 0 }

      it "creates a credit note" do
        travel_to(terminated_at) do
          result = create_service.call

          expect(result).to be_success

          credit_note = result.credit_note

          expect_credit_note_to_be_properly_defined(credit_note, total_amount_cents: 4_99, precise_item_amount_cents: 4_99.49999, tax_amount_cents: 0)
        end
      end
    end

    context "with a coupon applied to the invoice" do
      let(:invoice) do
        create(
          :invoice,
          organization:,
          customer:,
          currency: "EUR",
          fees_amount_cents: 31_00,
          total_amount_cents: 37_00,
          coupons_amount_cents: 10_00,
          taxes_amount_cents: 6_00,
          taxes_rate: tax_rate
        )
      end

      let(:subscription_fee) do
        create(
          :fee,
          subscription:,
          invoice:,
          amount_cents: 31_00,
          taxes_amount_cents: 6_00,
          invoiceable_type: "Subscription",
          invoiceable_id: subscription.id,
          taxes_rate: tax_rate,
          precise_coupons_amount_cents: 10_00,
          amount_details: {"plan_amount_cents" => plan.amount_cents}
        )
      end

      it "takes the coupon into account" do
        result = create_service.call

        expect(result).to be_success

        credit_note = result.credit_note

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
