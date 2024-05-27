# frozen_string_literal: true

require 'rails_helper'

describe 'Create credit note Scenarios', :scenarios, type: :request do
  let(:organization) { create(:organization, webhook_url: nil, email_settings: []) }
  let(:customer) { create(:customer, organization:) }

  let(:tax) { create(:tax, organization:, rate: 10) }

  let(:plan1) do
    create(
      :plan,
      organization:,
      interval: :monthly,
      amount_cents: 17_900,
      pay_in_advance: true,
    )
  end

  let(:plan2) do
    create(
      :plan,
      organization:,
      interval: :monthly,
      amount_cents: 39_900,
      pay_in_advance: true,
    )
  end

  let(:coupon) do
    create(
      :coupon,
      organization:,
      amount_cents: 20_000,
      expiration: :no_expiration,
      coupon_type: :fixed_amount,
      frequency: :forever,
      limited_plans: true,
    )
  end

  let(:coupon_target) do
    create(:coupon_plan, coupon:, plan: plan2)
  end

  let(:plan_tax) { create(:tax, organization:, name: 'Plan Tax', rate: 10, applied_to_organization: false) }
  let(:plan_applied_tax) { create(:plan_applied_tax, plan: plan2, tax: plan_tax) }
  let(:plan_applied_tax2) { create(:plan_applied_tax, plan: plan2, tax:) }

  around { |test| lago_premium!(&test) }

  before do
    tax
    plan_applied_tax
    plan_applied_tax2
  end

  it 'Allows creation of partial credit note' do
    # Creates two subscriptions
    travel_to(DateTime.new(2022, 12, 19, 12)) do
      create_subscription(
        external_customer_id: customer.external_id,
        external_id: "#{customer.external_id}_1",
        plan_code: plan1.code,
        billing_time: :anniversary,
      )

      create_subscription(
        external_customer_id: customer.external_id,
        external_id: "#{customer.external_id}_2",
        plan_code: plan2.code,
        billing_time: :anniversary,
      )
    end

    # Apply a coupon to the customer
    travel_to(DateTime.new(2023, 8, 29)) do
      apply_coupon(
        external_customer_id: customer.external_id,
        coupon_code: coupon_target.coupon.code,
        amount_cents: 250_00,
      )
    end

    # Bill subscription on an anniversary date
    travel_to(DateTime.new(2023, 10, 19)) do
      Subscriptions::BillingService.call
      perform_all_enqueued_jobs
    end

    invoice = customer.invoices.order(created_at: :desc).first
    expect(invoice.fees_amount_cents).to eq(57_800)
    expect(invoice.coupons_amount_cents).to eq(25_000)
    expect(invoice.taxes_rate).to eq(14.54268)
    expect(invoice.taxes_amount_cents).to eq(4_770)
    expect(invoice.total_amount_cents).to eq(37_570)

    fee1 = invoice.fees.find_by(amount_cents: 17_900)
    expect(fee1.precise_coupons_amount_cents).to eq(0)

    fee2 = invoice.fees.find_by(amount_cents: 39_900)
    expect(fee2.precise_coupons_amount_cents).to eq(25_000)

    travel_to(DateTime.new(2023, 10, 23)) do
      update_invoice(invoice, payment_status: :succeeded)

      # Estimate the credit notes amount on full fees
      estimate_credit_note(
        invoice_id: invoice.id,
        items: [
          {
            fee_id: fee1.id,
            amount_cents: fee1.amount_cents
          },
          {
            fee_id: fee2.id,
            amount_cents: fee2.amount_cents
          }
        ],
      )

      estimate = json[:estimated_credit_note]
      expect(estimate[:taxes_amount_cents]).to eq(4_770)
      expect(estimate[:sub_total_excluding_taxes_amount_cents]).to eq(32_800)
      expect(estimate[:max_creditable_amount_cents]).to eq(37_570)
      expect(estimate[:max_refundable_amount_cents]).to eq(37_570)
      expect(estimate[:coupons_adjustment_amount_cents]).to eq(250_00)
      expect(estimate[:taxes_rate]).to eq(14.54268)

      estimate_credit_note(
        invoice_id: invoice.id,
        items: [
          {
            fee_id: fee2.id,
            amount_cents: 26_260
          }
        ],
      )

      # Estimate the credit notes amount on one partial fee
      estimate = json[:estimated_credit_note]
      expect(estimate[:taxes_amount_cents]).to eq(1961)
      expect(estimate[:sub_total_excluding_taxes_amount_cents]).to eq(9_806)
      expect(estimate[:max_creditable_amount_cents]).to eq(11_768)
      expect(estimate[:max_refundable_amount_cents]).to eq(11_768)
      expect(estimate[:coupons_adjustment_amount_cents]).to eq(16_454)
      expect(estimate[:taxes_rate]).to eq(20)

      # Emit a credit note on only one fee
      create_credit_note(
        invoice_id: invoice.id,
        reason: :other,
        credit_amount_cents: 0,
        refund_amount_cents: 11_768,
        items: [
          {
            fee_id: fee2.id,
            amount_cents: 26_260
          }
        ],
      )
    end

    credit_note = invoice.credit_notes.first
    expect(credit_note.refund_amount_cents).to eq(11_768)
    expect(credit_note.total_amount_cents).to eq(11_768)
    expect(credit_note.coupons_adjustment_amount_cents).to eq(16_454)
  end

  context 'when applying multiple time the same coupon' do
    let(:plan) do
      create(
        :plan,
        organization:,
        interval: :monthly,
        amount_cents: 1_999,
        pay_in_advance: false,
      )
    end

    let(:charge1) do
      create(
        :standard_charge,
        plan:,
        min_amount_cents: 99_290,
      )
    end

    let(:charge2) do
      create(
        :standard_charge,
        plan:,
        min_amount_cents: 299_770,
      )
    end

    let(:charge3) do
      create(
        :standard_charge,
        plan:,
        min_amount_cents: 3_130,
      )
    end

    let(:charge4) do
      create(
        :standard_charge,
        plan:,
        min_amount_cents: 6_460,
      )
    end

    let(:charge5) do
      create(
        :standard_charge,
        plan:,
        min_amount_cents: 3_130,
      )
    end

    let(:coupon) do
      create(
        :coupon,
        organization:,
        amount_cents: 10_00,
        expiration: :no_expiration,
        coupon_type: :fixed_amount,
        frequency: :forever,
        limited_plans: false,
        reusable: true,
      )
    end

    before do
      charge1
      charge2
      charge3
      charge4
      charge5
    end

    it 'Allows creation of partial credit note' do
      # Creates two subscriptions
      travel_to(DateTime.new(2022, 12, 19, 12)) do
        create_subscription(
          external_customer_id: customer.external_id,
          external_id: "#{customer.external_id}_1",
          plan_code: plan.code,
          billing_time: :anniversary,
        )
      end

      # Apply a coupon twice to the customer
      travel_to(DateTime.new(2023, 8, 29)) do
        apply_coupon(
          external_customer_id: customer.external_id,
          coupon_code: coupon.code,
          amount_cents: 1_000,
        )

        apply_coupon(
          external_customer_id: customer.external_id,
          coupon_code: coupon.code,
          amount_cents: 1_000,
        )
      end

      # Bill subscription on an anniversary date
      travel_to(DateTime.new(2023, 10, 19)) do
        Subscriptions::BillingService.call
        perform_all_enqueued_jobs
      end

      invoice = customer.invoices.order(created_at: :desc).first
      expect(invoice.fees_amount_cents).to eq(413_779)
      expect(invoice.coupons_amount_cents).to eq(2_000)
      expect(invoice.taxes_rate).to eq(10)
      expect(invoice.taxes_amount_cents).to eq(41_178)
      expect(invoice.total_amount_cents).to eq(452_957)

      fee1 = invoice.fees.find_by(amount_cents: charge1.min_amount_cents)
      expect(fee1.precise_coupons_amount_cents).to eq(479.91802)

      fee2 = invoice.fees.find_by(amount_cents: charge2.min_amount_cents)
      expect(fee2.precise_coupons_amount_cents).to eq(1_448.93772)

      fee3 = invoice.fees.find_by(amount_cents: charge3.min_amount_cents)
      expect(fee3.precise_coupons_amount_cents).to eq(15.12884)

      fee4 = invoice.fees.find_by(amount_cents: charge4.min_amount_cents)
      expect(fee4.precise_coupons_amount_cents).to eq(31.2244)

      fee5 = invoice.fees.find_by(amount_cents: charge5.min_amount_cents)
      expect(fee5.precise_coupons_amount_cents).to eq(15.12884)

      fee6 = invoice.fees.find_by(amount_cents: plan.amount_cents)
      expect(fee6.precise_coupons_amount_cents).to eq(9.66216)

      travel_to(DateTime.new(2023, 10, 23)) do
        update_invoice(invoice, payment_status: :succeeded)

        estimate_credit_note(
          invoice_id: invoice.id,
          items: [
            {
              fee_id: fee6.id,
              amount_cents: 100
            },
            {
              fee_id: fee2.id,
              amount_cents: 100
            },
            {
              fee_id: fee3.id,
              amount_cents: 100
            },
            {
              fee_id: fee4.id,
              amount_cents: 100
            },
            {
              fee_id: fee5.id,
              amount_cents: 100
            }
          ],
        )

        estimate = json[:estimated_credit_note]
        expect(estimate[:coupons_adjustment_amount_cents]).to eq(2)
        expect(estimate[:sub_total_excluding_taxes_amount_cents]).to eq(498)
        expect(estimate[:taxes_amount_cents]).to eq(50)
        expect(estimate[:max_creditable_amount_cents]).to eq(547)
        expect(estimate[:max_refundable_amount_cents]).to eq(547)
        expect(estimate[:taxes_rate]).to eq(10)
      end
    end
  end
end
