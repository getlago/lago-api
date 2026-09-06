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
    let(:cycle_billing_at) { Time.zone.parse("2026-08-01") }
    let(:cycle_period_from) { Time.zone.parse("2026-08-01") }
    let(:cycle_period_to) { Time.zone.parse("2026-08-31 23:59:59.999999") }
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

    # `ended_at` is already set when this service runs: SubscriptionRateCards::TerminateService
    # sets it to terminated_at, in the same transaction, moments before. The schedule this
    # service builds has to see that state, or the boundary case below cannot be reproduced.
    let(:subscription_rate_card) do
      create(
        :subscription_rate_card,
        organization:,
        subscription:,
        customer:,
        rate_card:,
        billing_anchor_date: Date.parse("2026-01-01"),
        started_at: Time.zone.parse("2026-01-01"),
        ended_at: terminated_at,
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
        billing_at: cycle_billing_at,
        period_from: cycle_period_from,
        period_to: cycle_period_to,
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

      it "credits the unused amount using the period ratio containing the termination" do
        expect(result.credit_notes).to eq([credit_note])
        expect(CreditNotes::CreateService).to have_received(:call).with(
          invoice:,
          credit_amount_cents: 824,
          items: [
            {
              fee_id: Fee.sole.id,
              # The credited fraction is computed on the same basis the fee was priced on.
              # The fee bought the segment [Aug 15, Sep 1) — 17 days — of which 3 were
              # served, so 14/17 of it is unused. This used to read 903.22580, which is
              # 1000 x 28/31: the numerator counted days of the segment and the denominator
              # days of the whole 31-day cycle, crediting 9.7% of the fee that was never
              # charged on this segment in the first place.
              amount_cents: BigDecimal("823.52941")
            }
          ],
          reason: :order_cancellation,
          automatic: true
        )
      end
    end

    # The simple case has to be untouched by the basis fix: an uncut cycle is billed as one
    # segment, so the segment IS the cycle and both bases give the same number.
    context "when the advance cycle was billed as a single segment" do
      it "credits the unused days of the cycle" do
        expect(result.credit_notes).to eq([credit_note])
        expect(CreditNotes::CreateService).to have_received(:call).with(
          invoice:,
          credit_amount_cents: 452,
          items: [{fee_id: Fee.sole.id, amount_cents: BigDecimal("451.61290")}],
          reason: :order_cancellation,
          automatic: true
        )
      end
    end

    context "when the item is terminated exactly on a cycle boundary" do
      let(:terminated_at) { Time.zone.parse("2026-09-01 00:00:00") }
      let(:cycle_billing_at) { Time.zone.parse("2026-09-01") }
      let(:cycle_period_from) { Time.zone.parse("2026-09-01") }
      let(:cycle_period_to) { Time.zone.parse("2026-09-30 23:59:59.999999") }

      # The termination instant opens the billed cycle, and the fee and the ratio must be
      # read off that same cycle: reading the fee from September and the ratio from a fully
      # consumed August credited nothing at all.
      #
      # One day comes off, not none: terminating at 00:00 on Sep 1 still enters Sep 1, and a
      # day entered is a day paid for (Billing::TerminationDay). So 29 of 30 days are
      # refunded. This read 1000.0 while the termination day was excluded.
      it "credits every day after the one it terminated in" do
        expect(result.credit_notes).to eq([credit_note])
        expect(CreditNotes::CreateService).to have_received(:call).with(
          invoice:,
          credit_amount_cents: 967,
          items: [{fee_id: Fee.sole.id, amount_cents: BigDecimal("966.66666")}],
          reason: :order_cancellation,
          automatic: true
        )
      end
    end

    context "when the item is terminated mid-segment of a cut cycle" do
      let(:terminated_at) { Time.zone.parse("2026-03-21 00:00:00") }
      let(:cycle_billing_at) { Time.zone.parse("2026-03-01") }
      let(:cycle_period_from) { Time.zone.parse("2026-03-01") }
      let(:cycle_period_to) { Time.zone.parse("2026-03-31 23:59:59.999999") }

      before do
        create(
          :rate_card_rate,
          organization:,
          rate_card:,
          code: "rate_r1_v2",
          effective_from: Time.zone.parse("2026-03-16")
        )
      end

      # The fee bought the segment [Mar 16, Apr 1) — 16 days — of which 6 were entered and
      # so paid for. 10 of the 16 days remain, and 10/16 of the fee is credited. Measuring
      # the elapsed days against the 31-day cycle instead credited 26/31 = 838.70967,
      # over-crediting 15.121% of the fee.
      it "credits the unused days of the segment, not of the cycle" do
        expect(result.credit_notes).to eq([credit_note])
        expect(CreditNotes::CreateService).to have_received(:call).with(
          invoice:,
          credit_amount_cents: 625,
          items: [{fee_id: Fee.sole.id, amount_cents: BigDecimal("625.0")}],
          reason: :order_cancellation,
          automatic: true
        )
      end
    end

    context "when the item is terminated on the last instant of the billed segment" do
      let(:terminated_at) { Time.zone.parse("2026-08-31 23:59:59.999999") }

      before do
        create(
          :rate_card_rate,
          organization:,
          rate_card:,
          code: "rate_r1_v2",
          effective_from: Time.zone.parse("2026-08-15")
        )
      end

      it "credits nothing" do
        expect(result.credit_notes).to eq([])
        expect(CreditNotes::CreateService).not_to have_received(:call)
      end
    end

    context "when the item is terminated on the first instant of the billed segment" do
      let(:terminated_at) { Time.zone.parse("2026-08-15 00:00:00") }

      before do
        create(
          :rate_card_rate,
          organization:,
          rate_card:,
          code: "rate_r1_v2",
          effective_from: Time.zone.parse("2026-08-15")
        )
      end

      # All but the day it terminated in: opening a segment at its first instant still
      # enters that day, and a day entered is paid for. This read 1000.0 while the
      # termination day was excluded.
      it "credits every day of the segment after the one it terminated in" do
        expect(result.credit_notes).to eq([credit_note])
        expect(CreditNotes::CreateService).to have_received(:call).with(
          invoice:,
          credit_amount_cents: 941,
          items: [{fee_id: Fee.sole.id, amount_cents: BigDecimal("941.17647")}],
          reason: :order_cancellation,
          automatic: true
        )
      end
    end
  end
end
