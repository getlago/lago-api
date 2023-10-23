# frozen_string_literal: true

require 'rails_helper'

describe 'Create credit note Scenarios', :scenarios, type: :request do
  let(:organization) { create(:organization, webhook_url: nil, email_settings: []) }
  let(:customer) { create(:customer, organization:) }

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

  around { |test| lago_premium!(&test) }

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
    expect(invoice.total_amount_cents).to eq(32_800)

    fee1 = invoice.fees.find_by(amount_cents: 17_900)
    expect(fee1.precise_coupons_amount_cents).to eq(0)

    fee2 = invoice.fees.find_by(amount_cents: 39_900)
    expect(fee2.precise_coupons_amount_cents).to eq(25_000)

    # Emit a credit note on only one fee
    travel_to(DateTime.new(2023, 10, 23)) do
      update_invoice(invoice, payment_status: :succeeded)

      create_credit_note(
        invoice_id: invoice.id,
        reason: :other,
        credit_amount_cents: 0,
        refund_amount_cents: 14_902,
        items: [
          {
            fee_id: fee2.id,
            amount_cents: 26_260,
          },
        ],
      )
    end

    credit_note = invoice.credit_notes.first
    expect(credit_note.refund_amount_cents).to eq(14_902)
    expect(credit_note.total_amount_cents).to eq(14_902)
    expect(credit_note.coupons_adjustment_amount_cents).to eq(11_358)
  end
end
