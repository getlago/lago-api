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
      pay_in_advance: true
    )
  end

  let(:plan2) do
    create(
      :plan,
      organization:,
      interval: :monthly,
      amount_cents: 39_900,
      pay_in_advance: true
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
      limited_plans: true
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
        billing_time: :anniversary
      )

      create_subscription(
        external_customer_id: customer.external_id,
        external_id: "#{customer.external_id}_2",
        plan_code: plan2.code,
        billing_time: :anniversary
      )
    end

    # Apply a coupon to the customer
    travel_to(DateTime.new(2023, 8, 29)) do
      apply_coupon(
        external_customer_id: customer.external_id,
        coupon_code: coupon_target.coupon.code,
        amount_cents: 250_00
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
        ]
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
        ]
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
        ]
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
        pay_in_advance: false
      )
    end

    let(:charge1) do
      create(
        :standard_charge,
        plan:,
        min_amount_cents: 99_290
      )
    end

    let(:charge2) do
      create(
        :standard_charge,
        plan:,
        min_amount_cents: 299_770
      )
    end

    let(:charge3) do
      create(
        :standard_charge,
        plan:,
        min_amount_cents: 3_130
      )
    end

    let(:charge4) do
      create(
        :standard_charge,
        plan:,
        min_amount_cents: 6_460
      )
    end

    let(:charge5) do
      create(
        :standard_charge,
        plan:,
        min_amount_cents: 3_130
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
        reusable: true
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
          billing_time: :anniversary
        )
      end

      # Apply a coupon twice to the customer
      travel_to(DateTime.new(2023, 8, 29)) do
        apply_coupon(
          external_customer_id: customer.external_id,
          coupon_code: coupon.code,
          amount_cents: 1_000
        )

        apply_coupon(
          external_customer_id: customer.external_id,
          coupon_code: coupon.code,
          amount_cents: 1_000
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
          ]
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

  context 'when creating credit note with possible rounding issues' do
    context 'when creating credit notes for small items with taxes, so sum of items with their taxes is bigger than invoice total amount' do
      let(:tax) { create(:tax, organization:, rate: 20) }

      context 'when two similar items are refunded separately' do
        let(:add_ons) { create_list(:add_on, 2, organization:, amount_cents: 68_33) }

        it 'solves the rounding issue' do
          #  create a one off invoice with two addons and small amounts as feed
          create_one_off_invoice(customer, add_ons)
          # invoice amount should be with taxes calculated on items sum:
          invoice = customer.invoices.order(:created_at).last
          expect(invoice.total_amount_cents).to eq(163_99)
          expect(invoice.taxes_amount_cents).to eq(27_33)
          fees = invoice.fees
          invoice.update(payment_status: 'succeeded')

          # estimate and create credit notes for first item - full refund; the taxes are rounded to higher number
          estimate_credit_note(
            invoice_id: invoice.id,
            items: [
              {
                fee_id: fees[0].id,
                amount_cents: 68_33
              }
            ]
          )

          # Estimate the credit notes amount on one fee rounds the taxes to higher number
          estimate = json[:estimated_credit_note]
          expect(estimate).to include(
            taxes_amount_cents: 13_67,
            precise_taxes_amount_cents: "1366.6",
            sub_total_excluding_taxes_amount_cents: 6833,
            max_creditable_amount_cents: 8200,
            max_refundable_amount_cents: 8200,
            taxes_rate: 20.0
          )

          # Emit a credit note on only one fee
          create_credit_note(
            invoice_id: invoice.id,
            reason: :other,
            credit_amount_cents: 0,
            refund_amount_cents: 82_00,
            items: [
              {
                fee_id: fees[0].id,
                amount_cents: 68_33
              }
            ]
          )

          credit_note = invoice.credit_notes.order(:created_at).last
          expect(credit_note).to have_attributes(
            refund_amount_cents: 82_00,
            total_amount_cents: 82_00,
            taxes_amount_cents: 13_67,
            precise_taxes_amount_cents: 1366.6
          )
          expect(credit_note.precise_total).to eq(8199.6)
          expect(credit_note.taxes_rounding_adjustment).to eq(0.4)

          # when issuing second credit note, it should be rounded to lower number
          estimate_credit_note(
            invoice_id: invoice.id,
            items: [
              {
                fee_id: fees[1].id,
                amount_cents: 68_33
              }
            ]
          )

          estimate = json[:estimated_credit_note]
          expect(estimate).to include(
            taxes_amount_cents: 13_66,
            precise_taxes_amount_cents: "1366.2",
            sub_total_excluding_taxes_amount_cents: 6833,
            max_creditable_amount_cents: 8199,
            max_refundable_amount_cents: 8199,
            taxes_rate: 20.0
          )

          # Emit a credit note on only one fee
          create_credit_note(
            invoice_id: invoice.id,
            reason: :other,
            credit_amount_cents: 0,
            refund_amount_cents: 81_99,
            items: [
              {
                fee_id: fees[1].id,
                amount_cents: 68_33
              }
            ]
          )

          credit_note = invoice.credit_notes.order(:created_at).last
          expect(credit_note).to have_attributes(
            refund_amount_cents: 8199,
            total_amount_cents: 8199,
            taxes_amount_cents: 13_66,
            precise_taxes_amount_cents: 1366.2
          )
          expect(credit_note.precise_total).to eq(8199.2)
          expect(credit_note.taxes_rounding_adjustment).to eq(-0.2)
        end
      end

      context 'when four items are refunded separately, some whole, some in parts' do
        let(:add_ons) { create_list(:add_on, 4, organization:, amount_cents: 68_33) }

        it 'solves the rounding issue' do
          #  create a one off invoice with two addons and small amounts as feed
          create_one_off_invoice(customer, add_ons)
          # invoice amount should be with taxes calculated on items sum:
          invoice = customer.invoices.order(:created_at).last
          expect(invoice.total_amount_cents).to eq(327_98)
          expect(invoice.taxes_amount_cents).to eq(54_66)
          fees = invoice.fees
          invoice.update(payment_status: 'succeeded')

          # estimate and create credit notes for first three items - full refund; the taxes are rounded to higher number
          3.times do |i|
            estimate_credit_note(
              invoice_id: invoice.id,
              items: [
                {
                  fee_id: fees[i].id,
                  amount_cents: 68_33
                }
              ]
            )

            # Estimate the credit notes amount on one fee rounds the taxes to higher number
            estimate = json[:estimated_credit_note]
            expect(estimate).to include(
              taxes_amount_cents: 13_67,
              precise_taxes_amount_cents: "1366.6",
              sub_total_excluding_taxes_amount_cents: 6833,
              max_creditable_amount_cents: 8200,
              max_refundable_amount_cents: 8200,
              taxes_rate: 20.0
            )

            # Emit a credit note on only one fee
            create_credit_note(
              invoice_id: invoice.id,
              reason: :other,
              credit_amount_cents: 0,
              refund_amount_cents: 82_00,
              items: [
                {
                  fee_id: fees[i].id,
                  amount_cents: 68_33
                }
              ]
            )

            credit_note = invoice.credit_notes.order(:created_at).last
            expect(credit_note).to have_attributes(
              refund_amount_cents: 82_00,
              total_amount_cents: 82_00,
              taxes_amount_cents: 13_67,
              precise_taxes_amount_cents: 1366.6
            )
            expect(credit_note.precise_total).to eq(8199.6)
            expect(credit_note.taxes_rounding_adjustment).to eq(0.4)
          end
          # this value is wrong because of all rounding because if we subtract issued credit notes from the invoice, it
          # will result in 327_98 - 82_00 * 3 = 81_98
          expect(invoice.creditable_amount_cents).to eq(8200)

          # split last refundable item into three chunks, first's taxes are rounded to lower number
          # next two are rounded to higher number
          # cn_1 => 13.67, cn2 => 22.33, cn3 => 32.33
          # CN1
          estimate_credit_note(
            invoice_id: invoice.id,
            items: [
              {
                fee_id: fees[3].id,
                amount_cents: 13_67
              }
            ]
          )

          estimate = json[:estimated_credit_note]
          expect(estimate).to include(
            taxes_amount_cents: 273,
            precise_taxes_amount_cents: "273.4",
            sub_total_excluding_taxes_amount_cents: 1367,
            max_creditable_amount_cents: 1640,
            max_refundable_amount_cents: 1640,
            taxes_rate: 20.0
          )

          # Emit a credit note on only one fee
          create_credit_note(
            invoice_id: invoice.id,
            reason: :other,
            credit_amount_cents: 0,
            refund_amount_cents: 1640,
            items: [
              {
                fee_id: fees[3].id,
                amount_cents: 1367
              }
            ]
          )

          credit_note = invoice.credit_notes.order(:created_at).last
          expect(credit_note).to have_attributes(
            refund_amount_cents: 1640,
            total_amount_cents: 1640,
            taxes_amount_cents: 273,
            precise_taxes_amount_cents: 273.4
          )
          expect(credit_note.precise_total).to eq(1640.4)
          expect(credit_note.taxes_rounding_adjustment).to eq(-0.4)
          # real remaining: 81_98 - 16_40 = 65_58
          expect(invoice.creditable_amount_cents).to eq(6559)

          # cn_1 => 13.67, cn2 => 22.33, cn3 => 32.33
          # CN2
          estimate_credit_note(
            invoice_id: invoice.id,
            items: [
              {
                fee_id: fees[3].id,
                amount_cents: 22_33
              }
            ]
          )

          estimate = json[:estimated_credit_note]
          expect(estimate).to include(
            taxes_amount_cents: 447,
            precise_taxes_amount_cents: "446.6",
            sub_total_excluding_taxes_amount_cents: 2233,
            max_creditable_amount_cents: 2680,
            max_refundable_amount_cents: 2680,
            taxes_rate: 20.0
          )

          # Emit a credit note on only one fee
          create_credit_note(
            invoice_id: invoice.id,
            reason: :other,
            credit_amount_cents: 0,
            refund_amount_cents: 2680,
            items: [
              {
                fee_id: fees[3].id,
                amount_cents: 2233
              }
            ]
          )

          credit_note = invoice.credit_notes.order(:created_at).last
          expect(credit_note).to have_attributes(
            refund_amount_cents: 2680,
            total_amount_cents: 2680,
            taxes_amount_cents: 447,
            precise_taxes_amount_cents: 446.6
          )
          expect(credit_note.precise_total).to eq(2679.6)
          expect(credit_note.taxes_rounding_adjustment).to eq(0.4)
          # real remaining: 65_58 - 26_80 = 38_78
          expect(invoice.creditable_amount_cents).to eq(3880)

          # cn_1 => 13.67, cn2 => 22.33, cn3 => 32.33
          # CN3
          estimate_credit_note(
            invoice_id: invoice.id,
            items: [
              {
                fee_id: fees[3].id,
                amount_cents: 32_33
              }
            ]
          )

          estimate = json[:estimated_credit_note]
          expect(estimate).to include(
            taxes_amount_cents: 645,
            precise_taxes_amount_cents: "645.4",
            sub_total_excluding_taxes_amount_cents: 3233,
            max_creditable_amount_cents: 3878,
            max_refundable_amount_cents: 3878,
            taxes_rate: 20.0
          )

          # Emit a credit note on only one fee
          create_credit_note(
            invoice_id: invoice.id,
            reason: :other,
            credit_amount_cents: 0,
            refund_amount_cents: 3878,
            items: [
              {
                fee_id: fees[3].id,
                amount_cents: 3233
              }
            ]
          )

          credit_note = invoice.credit_notes.order(:created_at).last
          expect(credit_note).to have_attributes(
            refund_amount_cents: 3878,
            total_amount_cents: 3878,
            taxes_amount_cents: 645,
            precise_taxes_amount_cents: 645.4
          )
          expect(credit_note.precise_total).to eq(3878.4)
          expect(credit_note.taxes_rounding_adjustment).to eq(-0.4)
          expect(invoice.creditable_amount_cents).to eq(0)
        end
      end
    end

    context 'when creating credit note with small items and applied coupons' do
      let(:tax) { create(:tax, organization:, rate: 20) }
      let(:plan_tax) { create(:tax, organization:, name: 'Plan Tax', rate: 20, applied_to_organization: false) }
      let(:plan) do
        create(
          :plan,
          organization:,
          interval: :monthly,
          amount_cents: 1_999,
          pay_in_advance: false
        )
      end

      let(:charge1) do
        create(
          :standard_charge,
          plan:,
          min_amount_cents: 6833
        )
      end

      let(:charge2) do
        create(
          :standard_charge,
          plan:,
          min_amount_cents: 200_33
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
          reusable: true
        )
      end

      before do
        charge1
        charge2
      end

      it 'calculates all roundings' do
        # Creates two subscriptions
        travel_to(DateTime.new(2022, 12, 19, 12)) do
          create_subscription(
            external_customer_id: customer.external_id,
            external_id: "#{customer.external_id}_1",
            plan_code: plan.code,
            billing_time: :anniversary
          )
        end

        # Apply a coupon twice to the customer
        travel_to(DateTime.new(2023, 8, 29)) do
          apply_coupon(
            external_customer_id: customer.external_id,
            coupon_code: coupon.code,
            amount_cents: 10_00
          )
        end

        # Bill subscription on an anniversary date
        travel_to(DateTime.new(2023, 10, 19)) do
          Subscriptions::BillingService.call
          perform_all_enqueued_jobs
        end

        invoice = customer.invoices.order(created_at: :desc).first
        # fees sum = 19_99 + 68_33 + 200_33 = 288_65
        # applied coupon - 10_00
        # subtotal before taxes - 278_65
        # taxes = 5573
        expect(invoice.total_amount_cents).to eq(334_38)

        # issue a CN for the full subscription fee - 19_99 before taxes and coupons
        subscription_fee = invoice.fees.find(&:subscription?)
        estimate_credit_note(
          invoice_id: invoice.id,
          items: [
            {
              fee_id: subscription_fee.id,
              amount_cents: 19_99
            }
          ]
        )

        estimate = json[:estimated_credit_note]
        expect(estimate).to include(
          taxes_amount_cents: 386,
          precise_taxes_amount_cents: "386.0",
          sub_total_excluding_taxes_amount_cents: 1930,
          max_creditable_amount_cents: 2316,
          coupons_adjustment_amount_cents: 69,
          taxes_rate: 20.0
        )
        create_credit_note(
          invoice_id: invoice.id,
          reason: :other,
          credit_amount_cents: 23_16,
          items: [
            {
              fee_id: subscription_fee.id,
              amount_cents: 19_99
            }
          ]
        )

        credit_note = invoice.credit_notes.order(:created_at).last
        expect(credit_note).to have_attributes(
          credit_amount_cents: 2316,
          total_amount_cents: 2316,
          taxes_amount_cents: 386,
          precise_taxes_amount_cents: 386.0,
          precise_coupons_adjustment_amount_cents: 69.25342
        )
        expect(credit_note.precise_total).to eq(2315.74658)
        expect(credit_note.taxes_rounding_adjustment).to eq(0)
        # real remaining: 334_38 - 23_16 = 311_22
        expect(invoice.creditable_amount_cents).to eq(31122.253421098216)

        # issue a CN for the full first charge - 68_33 before taxes and coupons
        first_charge = invoice.fees.find { |fee| fee.amount_cents == 68_33 }
        estimate_credit_note(
          invoice_id: invoice.id,
          items: [
            {
              fee_id: first_charge.id,
              amount_cents: 68_33
            }
          ]
        )

        estimate = json[:estimated_credit_note]
        expect(estimate).to include(
          taxes_amount_cents: 1319,
          precise_taxes_amount_cents: "1319.2",
          sub_total_excluding_taxes_amount_cents: 6596,
          max_creditable_amount_cents: 7915,
          coupons_adjustment_amount_cents: 237,
          taxes_rate: 20.0
        )
        create_credit_note(
          invoice_id: invoice.id,
          reason: :other,
          credit_amount_cents: 7915,
          items: [
            {
              fee_id: first_charge.id,
              amount_cents: 6833
            }
          ]
        )

        credit_note = invoice.credit_notes.order(:created_at).last
        expect(credit_note).to have_attributes(
          credit_amount_cents: 7915,
          total_amount_cents: 7915,
          taxes_amount_cents: 1319,
          precise_taxes_amount_cents: 1319.2,
          precise_coupons_adjustment_amount_cents: 236.72267
        )
        expect(credit_note.precise_total).to eq(7915.47733)
        expect(credit_note.taxes_rounding_adjustment).to eq(-0.2)
        # real remaining: 311_22 - 79_15 = 232_07
        expect(invoice.creditable_amount_cents).to eq(23206.97609561753)

        # issue a CN for the full last charge - 200_33 before taxes and coupons
        last_charge = invoice.fees.find { |fee| fee.amount_cents == 200_33 }
        estimate_credit_note(
          invoice_id: invoice.id,
          items: [
            {
              fee_id: last_charge.id,
              amount_cents: 200_33
            }
          ]
        )

        estimate = json[:estimated_credit_note]
        expect(estimate).to include(
          taxes_amount_cents: 3868,
          precise_taxes_amount_cents: "3868.0",
          sub_total_excluding_taxes_amount_cents: 19339,
          max_creditable_amount_cents: 23207,
          coupons_adjustment_amount_cents: 694,
          taxes_rate: 20.0
        )
        create_credit_note(
          invoice_id: invoice.id,
          reason: :other,
          credit_amount_cents: 23207,
          items: [
            {
              fee_id: last_charge.id,
              amount_cents: 200_33
            }
          ]
        )

        credit_note = invoice.credit_notes.order(:created_at).last
        expect(credit_note).to have_attributes(
          credit_amount_cents: 23207,
          total_amount_cents: 23207,
          taxes_amount_cents: 3868,
          precise_taxes_amount_cents: 3868.0,
          precise_coupons_adjustment_amount_cents: 694.0239
        )
        expect(credit_note.precise_total).to eq(23206.9761)
        expect(credit_note.taxes_rounding_adjustment).to eq(0)
        # real remaining: 232_07 - 23_207 = 0
        expect(invoice.creditable_amount_cents).to eq(0)
      end
    end
  end

  context 'when invoice is prepaid credit' do
    it 'behaves differently depending on the invoice payment status, wallet balance and wallet status' do
      # Create a prepaid credit invoice for 15 credits
      create_wallet({
        external_customer_id: customer.external_id,
        rate_amount: '1',
        name: 'Wallet1',
        currency: 'EUR',
        invoice_requires_successful_payment: false # default
      })
      wallet = customer.wallets.sole

      create_wallet_transaction({
        wallet_id: wallet.id,
        paid_credits: '15'
      })
      wt = WalletTransaction.find json[:wallet_transactions].first[:lago_id]

      expect(wt.status).to eq 'pending'
      expect(wt.transaction_status).to eq 'purchased'

      # Customer does not have a payment_provider set yet
      invoice = customer.invoices.credit.sole
      expect(invoice.status).to eq 'finalized'

      # it does not allow to create credit notes on invoices with payment status pending
      expect(invoice.creditable_amount_cents).to eq 0
      expect(invoice.refundable_amount_cents).to eq 0

      estimate_credit_note(
        invoice_id: invoice.id,
        items: [
          {
            fee_id: invoice.fees.first.id,
            amount_cents: 15
          }
        ]
      )
      expect(response).to have_http_status(:method_not_allowed)

      # pay the invoice
      update_invoice(invoice, payment_status: :succeeded)
      perform_all_enqueued_jobs
      wallet.reload
      expect(wallet.balance_cents).to eq 1500

      # it allows to estimate a credit notes on credit invoices with payment status succeeded
      estimate_credit_note(
        invoice_id: invoice.id,
        items: [
          {
            fee_id: invoice.fees.first.id,
            amount_cents: 10
          }
        ]
      )
      estimate = json[:estimated_credit_note]
      expect(estimate[:sub_total_excluding_taxes_amount_cents]).to eq(10)
      expect(estimate[:max_refundable_amount_cents]).to eq(10)
      expect(estimate[:max_creditable_amount_cents]).to eq(0)

      # when estimating a credit note with amount higher than the remaining balance, it will return the remaining balance
      wallet.update(balance_cents: 5)
      estimate_credit_note(
        invoice_id: invoice.id,
        items: [
          {
            fee_id: invoice.fees.first.id,
            amount_cents: 10
          }
        ]
      )
      estimate = json[:estimated_credit_note]
      expect(estimate[:sub_total_excluding_taxes_amount_cents]).to eq(10)
      expect(estimate[:max_refundable_amount_cents]).to eq(5)
      expect(estimate[:max_creditable_amount_cents]).to eq(0)
    end
  end
end
