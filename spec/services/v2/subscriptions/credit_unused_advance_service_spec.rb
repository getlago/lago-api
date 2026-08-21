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
          credit_amount_cents: 903,
          items: [
            {
              fee_id: Fee.sole.id,
              amount_cents: BigDecimal("903.22580")
            }
          ],
          reason: :order_cancellation,
          automatic: true
        )
      end
    end
  end
end
