# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Credits::AppliedCouponsService do
  subject(:credit_service) { described_class.new(invoice:) }

  let(:invoice) do
    create(
      :invoice,
      amount_cents: 100,
      vat_amount_cents: 20,
      total_amount_cents: 120,
      amount_currency: 'EUR',
      customer: subscription.customer,
    )
  end

  let(:subscription) do
    create(
      :subscription,
      plan:,
      billing_time: :calendar,
      subscription_at: started_at,
      started_at:,
      created_at:,
      status: :active,
    )
  end
  let(:started_at) { Time.zone.now - 2.years }
  let(:created_at) { started_at }

  describe '#create' do
    let(:timestamp) { Time.zone.now.beginning_of_month }
    let(:applied_coupon) do
      create(
        :applied_coupon,
        customer: subscription.customer,
        amount_cents: 10,
        amount_currency: plan.amount_currency,
      )
    end
    let(:coupon_latest) { create(:coupon, coupon_type: 'percentage') }
    let(:applied_coupon_latest) do
      create(
        :applied_coupon,
        coupon: coupon_latest,
        customer: subscription.customer,
        percentage_rate: 20.00,
        created_at: applied_coupon.created_at + 1.day,
      )
    end

    let(:plan) { create(:plan, interval: 'monthly') }

    before do
      create(:invoice_subscription, invoice:, subscription:)
      create(:fee, invoice:, subscription:)
      applied_coupon
      applied_coupon_latest
    end

    it 'updates the invoice accordingly' do
      result = credit_service.create

      aggregate_failures do
        expect(result).to be_success
        expect(result.invoice.credit_amount_cents).to eq(32)
        expect(result.invoice.total_amount_cents).to eq(88)
        expect(result.invoice.credits.count).to eq(2)
      end
    end

    context 'when both coupons are fixed amount' do
      let(:coupon_latest) { create(:coupon, coupon_type: 'fixed_amount') }
      let(:applied_coupon_latest) do
        create(
          :applied_coupon,
          coupon: coupon_latest,
          customer: subscription.customer,
          amount_cents: 20,
          amount_currency: plan.amount_currency,
          created_at: applied_coupon.created_at + 1.day,
        )
      end

      it 'updates the invoice accordingly' do
        result = credit_service.create

        aggregate_failures do
          expect(result).to be_success
          expect(result.invoice.amount_cents).to eq(100)
          expect(result.invoice.vat_amount_cents).to eq(20)
          expect(result.invoice.total_amount_cents).to eq(90)
          expect(result.invoice.credits.count).to eq(2)
        end
      end
    end

    context 'when both coupons are percentage' do
      let(:coupon) { create(:coupon, coupon_type: 'percentage') }
      let(:applied_coupon) do
        create(
          :applied_coupon,
          coupon:,
          customer: subscription.customer,
          percentage_rate: 15.00,
        )
      end

      it 'updates the invoice accordingly' do
        result = credit_service.create

        aggregate_failures do
          expect(result).to be_success
          expect(result.invoice.amount_cents).to eq(100)
          expect(result.invoice.vat_amount_cents).to eq(20)
          expect(result.invoice.total_amount_cents).to eq(82)
          expect(result.invoice.credits.count).to eq(2)
        end
      end
    end

    context 'when coupon has a difference currency' do
      let(:applied_coupon) do
        create(
          :applied_coupon,
          customer: subscription.customer,
          amount_cents: 10,
          amount_currency: 'NOK',
        )
      end

      before { applied_coupon_latest.update!(status: :terminated) }

      it 'ignores the coupon' do
        result = credit_service.create

        expect(result).to be_success
        expect(result.invoice.credits.count).to be_zero
      end
    end

    context 'when both coupons have plan limitations which are not applicable' do
      let(:coupon) { create(:coupon, coupon_type: 'fixed_amount', limited_plans: true) }
      let(:coupon_plan) { create(:coupon_plan, coupon:, plan: create(:plan)) }
      let(:applied_coupon) do
        create(
          :applied_coupon,
          coupon:,
          customer: subscription.customer,
          amount_cents: 10,
          amount_currency: plan.amount_currency,
        )
      end
      let(:coupon_latest) { create(:coupon, coupon_type: 'fixed_amount', limited_plans: true) }
      let(:coupon_plan_latest) { create(:coupon_plan, coupon: coupon_latest, plan: create(:plan)) }
      let(:applied_coupon_latest) do
        create(
          :applied_coupon,
          coupon: coupon_latest,
          customer: subscription.customer,
          amount_cents: 20,
          amount_currency: plan.amount_currency,
          created_at: applied_coupon.created_at + 1.day,
        )
      end

      before do
        coupon_plan
        coupon_plan_latest
      end

      it 'ignores coupons' do
        result = credit_service.create

        aggregate_failures do
          expect(result).to be_success
          expect(result.invoice.amount_cents).to eq(100)
          expect(result.invoice.vat_amount_cents).to eq(20)
          expect(result.invoice.total_amount_cents).to eq(120)
          expect(result.invoice.credits.count).to be_zero
        end
      end
    end

    context 'when only one coupon is applicable due to plan limitations' do
      let(:coupon) { create(:coupon, coupon_type: 'fixed_amount', limited_plans: true) }
      let(:coupon_plan) { create(:coupon_plan, coupon:, plan: create(:plan)) }
      let(:applied_coupon) do
        create(
          :applied_coupon,
          coupon:,
          customer: subscription.customer,
          amount_cents: 10,
          amount_currency: plan.amount_currency,
        )
      end
      let(:coupon_latest) { create(:coupon, coupon_type: 'fixed_amount', limited_plans: true) }
      let(:coupon_plan_latest) { create(:coupon_plan, coupon: coupon_latest, plan:) }
      let(:applied_coupon_latest) do
        create(
          :applied_coupon,
          coupon: coupon_latest,
          customer: subscription.customer,
          amount_cents: 20,
          amount_currency: plan.amount_currency,
          created_at: applied_coupon.created_at + 1.day,
        )
      end

      before do
        coupon_plan
        coupon_plan_latest
      end

      it 'ignores only one coupon and applies the other one' do
        result = credit_service.create

        aggregate_failures do
          expect(result).to be_success
          expect(result.invoice.total_amount_cents).to eq(100)
          expect(result.invoice.credits.count).to eq(1)
        end
      end
    end

    context 'when both coupons are applicable due to plan limitations' do
      let(:coupon) { create(:coupon, coupon_type: 'fixed_amount', limited_plans: true) }
      let(:coupon_plan) { create(:coupon_plan, coupon:, plan:) }
      let(:applied_coupon) do
        create(
          :applied_coupon,
          coupon:,
          customer: subscription.customer,
          amount_cents: 10,
          amount_currency: plan.amount_currency,
        )
      end
      let(:coupon_latest) { create(:coupon, coupon_type: 'fixed_amount', limited_plans: true) }
      let(:coupon_plan_latest) { create(:coupon_plan, coupon: coupon_latest, plan:) }
      let(:applied_coupon_latest) do
        create(
          :applied_coupon,
          coupon: coupon_latest,
          customer: subscription.customer,
          amount_cents: 20,
          amount_currency: plan.amount_currency,
          created_at: applied_coupon.created_at + 1.day,
        )
      end

      before do
        coupon_plan
        coupon_plan_latest
      end

      it 'applies two coupons' do
        result = credit_service.create

        aggregate_failures do
          expect(result).to be_success
          expect(result.invoice.total_amount_cents).to eq(90)
          expect(result.invoice.credits.count).to eq(2)
        end
      end
    end
  end
end
