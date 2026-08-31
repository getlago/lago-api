# frozen_string_literal: true

require "rails_helper"

RSpec.describe V2::Subscriptions::CreditUnusedAdvanceService do
  describe ".call" do
    subject(:result) { described_class.call(subscription:, terminated_at:) }

    let(:terminated_at) { Time.zone.parse("2026-08-17 12:34:56") }
    let(:organization) { create(:organization) }
    let(:customer) { create(:customer, organization:) }
    let(:plan) { create(:plan, organization:) }
    let(:subscription) { create(:subscription, organization:, customer:, plan:) }
    let(:rate_card) { create(:rate_card, :advance, organization:) }
    let(:credit_note) { instance_double(CreditNote) }
    let(:taxes_result) do
      CreditNotes::ApplyTaxesService::Result.new.tap do |result|
        result.coupons_adjustment_amount_cents = 0
        result.precise_taxes_amount_cents = 0
      end
    end
    let(:credit_result) do
      CreditNotes::CreateService::Result.new.tap do |result|
        result.credit_note = credit_note
      end
    end
    let(:subscription_rate_card) do
      create(
        :subscription_rate_card,
        organization:,
        subscription:,
        customer:,
        rate_card:,
        billing_anchor_date: Date.parse("2026-01-01"),
        started_at: Time.zone.parse("2026-01-01"),
        next_billing_at: Time.zone.parse("2026-09-01")
      )
    end
    let(:invoice) { create(:invoice, :subscription, organization:, customer:, subscriptions: [subscription]) }

    before do
      create(:rate_card_rate, organization:, rate_card:, effective_from: Time.zone.parse("2026-01-01"))
      create(
        :billing_cycle,
        organization:,
        subscription:,
        customer:,
        subscription_rate_card:,
        billing_at: Time.zone.parse("2026-08-01"),
        period_from: Time.zone.parse("2026-08-01"),
        period_to: Time.zone.parse("2026-08-31 23:59:59.999999"),
        invoice:,
        status: :done
      )
      create(
        :fee,
        organization:,
        subscription:,
        invoice:,
        invoiceable: subscription_rate_card.product,
        amount_cents: 1_000
      )
      allow(CreditNotes::ApplyTaxesService).to receive(:call).and_return(taxes_result)
      allow(CreditNotes::CreateService).to receive(:call).and_return(credit_result)
    end

    it "credits the days of the billed period the customer never got" do
      expect(result.credit_notes).to eq([credit_note])
      expect(CreditNotes::CreateService).to have_received(:call).with(
        invoice:,
        credit_amount_cents: 452,
        items: [{fee_id: Fee.sole.id, amount_cents: BigDecimal("451.61290")}],
        reason: :order_cancellation,
        automatic: true
      )
    end

    # The termination day is billed in full either way, so the hour it happens at must not
    # move the credit. QA plan X1 pins the day as inclusive (16 days, not 15).
    context "when the termination lands exactly on midnight" do
      let(:terminated_at) { Time.zone.parse("2026-08-17 00:00:00") }

      it "credits the same as a termination later that day" do
        expect(result.credit_notes).to eq([credit_note])
        expect(CreditNotes::CreateService).to have_received(:call).with(
          hash_including(items: [{fee_id: Fee.sole.id, amount_cents: BigDecimal("451.61290")}])
        )
      end
    end

    context "when the termination lands on the closing boundary" do
      let(:terminated_at) { Time.zone.parse("2026-08-31 23:59:59") }

      it "credits nothing, the period was fully consumed" do
        expect(result.credit_notes).to be_empty
        expect(CreditNotes::CreateService).not_to have_received(:call)
      end
    end

    # QA plan v2, scenario X2: a 30-day advance period Sep 10 -> Oct 9 paid at 150.00,
    # terminated on Sep 25. Expected credit is the 14 unused days, Sep 26 -> Oct 9, at
    # 70.00. The termination day itself counts as consumed.
    context "with the QA plan X2 scenario" do
      let(:terminated_at) { Time.zone.parse("2026-09-25") }
      let(:subscription_rate_card) do
        create(
          :subscription_rate_card,
          organization:, subscription:, customer:, rate_card:,
          billing_anchor_date: Date.parse("2026-08-10"),
          started_at: Time.zone.parse("2026-08-10"),
          next_billing_at: Time.zone.parse("2026-10-10")
        )
      end

      before do
        BillingCycle.sole.update!(
          billing_at: Time.zone.parse("2026-09-10"),
          period_from: Time.zone.parse("2026-09-10"),
          period_to: Time.zone.parse("2026-10-09 23:59:59.999999")
        )
        Fee.sole.update!(amount_cents: 15_000)
      end

      it "credits the fourteen unused days" do
        expect(result.credit_notes).to eq([credit_note])
        expect(CreditNotes::CreateService).to have_received(:call).with(
          hash_including(credit_amount_cents: 7_000)
        )
      end
    end

    context "when the advance cycle contains two rate periods" do
      before do
        create(
          :rate_card_rate,
          organization:,
          rate_card:,
          code: "rate_r1_v2",
          effective_from: Time.zone.parse("2026-08-15")
        )
      end

      # The credit is measured against the period the cycle actually billed — Aug 1 to
      # Aug 31 — not against the slice opened by the rate change on Aug 15. The customer
      # paid 1000 up front for the whole month and used 17 of its 31 days, so 14/31 is
      # refundable. Measuring from the rate change instead would refund 903 to someone
      # who consumed more than half the period.
      it "credits the unused share of the period the cycle billed" do
        expect(result.credit_notes).to eq([credit_note])
        expect(CreditNotes::CreateService).to have_received(:call).with(
          invoice:,
          credit_amount_cents: 452,
          items: [
            {
              fee_id: Fee.sole.id,
              amount_cents: BigDecimal("451.61290")
            }
          ],
          reason: :order_cancellation,
          automatic: true
        )
      end
    end
  end
end
