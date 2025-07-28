# frozen_string_literal: true

require "rails_helper"

describe "Coupons breakdown Spec", :scenarios, type: :request do
  let(:organization) { create(:organization, webhook_url: nil, premium_integrations: ["progressive_billing"]) }

  before do
    organization
    stub_pdf_generation
  end

  around { |test| lago_premium!(&test) }

  context "when there are multiple subscriptions and coupons of different kinds" do
    it "creates an invoice for the expected period" do
      create_metric(name: "Name", code: "bm1", aggregation_type: "sum_agg", field_name: "total1")
      bm1 = organization.billable_metrics.find_by(code: "bm1")

      create_metric(name: "Name", code: "bm2", aggregation_type: "sum_agg", field_name: "total2")
      bm2 = organization.billable_metrics.find_by(code: "bm2")

      create_metric(name: "Name", code: "bm3", aggregation_type: "sum_agg", field_name: "total3")
      bm3 = organization.billable_metrics.find_by(code: "bm3")

      create_metric(name: "Name", code: "bm4", aggregation_type: "sum_agg", field_name: "total4")
      bm4 = organization.billable_metrics.find_by(code: "bm4")

      create_metric(name: "Name", code: "bm5", aggregation_type: "sum_agg", field_name: "total5")
      bm5 = organization.billable_metrics.find_by(code: "bm5")

      create_metric(name: "Name", code: "bm6", aggregation_type: "sum_agg", field_name: "total6")
      bm6 = organization.billable_metrics.find_by(code: "bm6")

      create_metric(name: "Name", code: "bm7", aggregation_type: "sum_agg", field_name: "total7")
      bm7 = organization.billable_metrics.find_by(code: "bm7")

      create_metric(name: "Name", code: "bm8", aggregation_type: "sum_agg", field_name: "total8")
      bm8 = organization.billable_metrics.find_by(code: "bm8")

      travel_to(DateTime.new(2023, 1, 1)) do
        create_tax(name: "Banking rates 1", code: "banking_rates1", rate: 10.0)
        create_tax(name: "Banking rates 2", code: "banking_rates2", rate: 20.0)

        create_or_update_customer(external_id: "customer-12345")

        create_plan(
          {
            name: "P1",
            code: "plan_code",
            interval: "monthly",
            amount_cents: 0,
            amount_currency: "EUR",
            pay_in_advance: false,
            charges: [
              {
                billable_metric_id: bm1.id,
                charge_model: "standard",
                properties: {amount: "1"},
                tax_codes: [organization.taxes.find_by(code: "banking_rates1").code]
              },
              {
                billable_metric_id: bm2.id,
                charge_model: "standard",
                properties: {amount: "1"},
                tax_codes: [organization.taxes.find_by(code: "banking_rates2").code]
              },
              {
                billable_metric_id: bm3.id,
                charge_model: "standard",
                properties: {amount: "1"},
                tax_codes: [organization.taxes.find_by(code: "banking_rates1").code]
              },
              {
                billable_metric_id: bm4.id,
                charge_model: "standard",
                properties: {amount: "1"},
                tax_codes: [organization.taxes.find_by(code: "banking_rates1").code]
              }
            ]
          }
        )
        plan = organization.plans.find_by(code: "plan_code")

        create_subscription(
          {
            external_customer_id: "customer-12345",
            external_id: "sub_external_id",
            plan_code: plan.code
          }
        )

        create_plan(
          {
            name: "P2",
            code: "plan_code2",
            interval: "monthly",
            amount_cents: 0,
            amount_currency: "EUR",
            pay_in_advance: false,
            charges: [
              {
                billable_metric_id: bm5.id,
                charge_model: "standard",
                properties: {amount: "1"},
                tax_codes: [organization.taxes.find_by(code: "banking_rates1").code]
              },
              {
                billable_metric_id: bm6.id,
                charge_model: "standard",
                properties: {amount: "1"},
                tax_codes: [organization.taxes.find_by(code: "banking_rates2").code]
              },
              {
                billable_metric_id: bm7.id,
                charge_model: "standard",
                properties: {amount: "1"},
                tax_codes: [organization.taxes.find_by(code: "banking_rates1").code]
              },
              {
                billable_metric_id: bm8.id,
                charge_model: "standard",
                properties: {amount: "1"},
                tax_codes: [organization.taxes.find_by(code: "banking_rates1").code]
              }
            ]
          }
        )
        plan2 = organization.plans.find_by(code: "plan_code2")

        create_subscription(
          {
            external_customer_id: "customer-12345",
            external_id: "sub_external_id2",
            plan_code: plan2.code
          }
        )

        create_coupon(
          {
            name: "coupon1",
            code: "coupon1_code",
            coupon_type: "fixed_amount",
            frequency: "once",
            amount_cents: 2_000,
            amount_currency: "EUR",
            expiration: "time_limit",
            expiration_at: Time.current + 50.days,
            reusable: false,
            applies_to: {
              billable_metric_codes: [bm1.code, bm2.code]
            }
          }
        )
        apply_coupon({external_customer_id: "customer-12345", coupon_code: "coupon1_code"})

        create_coupon(
          {
            name: "coupon2",
            code: "coupon2_code",
            coupon_type: "fixed_amount",
            frequency: "once",
            amount_cents: 1_000,
            amount_currency: "EUR",
            expiration: "time_limit",
            expiration_at: Time.current + 50.days,
            reusable: false,
            applies_to: {
              plan_codes: [plan2.code]
            }
          }
        )
        apply_coupon({external_customer_id: "customer-12345", coupon_code: "coupon2_code"})

        create_coupon(
          {
            name: "coupon3",
            code: "coupon3_code",
            coupon_type: "fixed_amount",
            frequency: "once",
            amount_cents: 500,
            amount_currency: "EUR",
            expiration: "time_limit",
            expiration_at: Time.current + 50.days,
            reusable: false
          }
        )
        apply_coupon({external_customer_id: "customer-12345", coupon_code: "coupon3_code"})

        # First subscription events
        create_event(
          {
            code: bm1.code,
            transaction_id: SecureRandom.uuid,
            external_subscription_id: "sub_external_id",
            properties: {total1: 10}
          }
        )
        create_event(
          {
            code: bm2.code,
            transaction_id: SecureRandom.uuid,
            external_subscription_id: "sub_external_id",
            properties: {total2: 20}
          }
        )
        create_event(
          {
            code: bm3.code,
            transaction_id: SecureRandom.uuid,
            external_subscription_id: "sub_external_id",
            properties: {total3: 30}
          }
        )
        create_event(
          {
            code: bm4.code,
            transaction_id: SecureRandom.uuid,
            external_subscription_id: "sub_external_id",
            properties: {total4: 40}
          }
        )

        # Second subscription events
        create_event(
          {
            code: bm5.code,
            transaction_id: SecureRandom.uuid,
            external_subscription_id: "sub_external_id2",
            properties: {total5: 10}
          }
        )
        create_event(
          {
            code: bm6.code,
            transaction_id: SecureRandom.uuid,
            external_subscription_id: "sub_external_id2",
            properties: {total6: 20}
          }
        )
        create_event(
          {
            code: bm7.code,
            transaction_id: SecureRandom.uuid,
            external_subscription_id: "sub_external_id2",
            properties: {total7: 30}
          }
        )
        create_event(
          {
            code: bm8.code,
            transaction_id: SecureRandom.uuid,
            external_subscription_id: "sub_external_id2",
            properties: {total8: 40}
          }
        )
      end

      travel_to(DateTime.new(2023, 2, 1)) do
        perform_billing
      end

      customer = organization.customers.find_by(external_id: "customer-12345")
      invoice = customer.invoices.first
      fees = invoice.fees
      subscription1 = Subscription.find_by(external_id: "sub_external_id")
      subscription2 = Subscription.find_by(external_id: "sub_external_id2")
      sub1_fees = fees.charge.where(subscription: subscription1).joins(:charge)
      sub2_fees = fees.charge.where(subscription: subscription2).joins(:charge)

      # Subscription 1 fees
      expect(sub1_fees.where(charge: {billable_metric_id: bm1.id}).first).to have_attributes(
        amount_cents: 1_000,
        taxes_amount_cents: 32,
        taxes_rate: 10.0,
        precise_coupons_amount_cents: 676.47059
      )
      expect(sub1_fees.where(charge: {billable_metric_id: bm2.id}).first).to have_attributes(
        amount_cents: 2_000,
        taxes_amount_cents: 129,
        taxes_rate: 20.0,
        precise_coupons_amount_cents: 1352.94117
      )
      expect(sub1_fees.where(charge: {billable_metric_id: bm3.id}).first).to have_attributes(
        amount_cents: 3_000,
        taxes_amount_cents: 291,
        taxes_rate: 10.0,
        precise_coupons_amount_cents: 88.23529
      )
      expect(sub1_fees.where(charge: {billable_metric_id: bm4.id}).first).to have_attributes(
        amount_cents: 4_000,
        taxes_amount_cents: 388,
        taxes_rate: 10.0,
        precise_coupons_amount_cents: 117.64706
      )

      # Subscription 2 fees
      expect(sub2_fees.where(charge: {billable_metric_id: bm5.id}).first).to have_attributes(
        amount_cents: 1_000,
        taxes_amount_cents: 87,
        taxes_rate: 10.0,
        precise_coupons_amount_cents: 126.47059
      )
      expect(sub2_fees.where(charge: {billable_metric_id: bm6.id}).first).to have_attributes(
        amount_cents: 2_000,
        taxes_amount_cents: 349,
        taxes_rate: 20.0,
        precise_coupons_amount_cents: 252.94118
      )
      expect(sub2_fees.where(charge: {billable_metric_id: bm7.id}).first).to have_attributes(
        amount_cents: 3_000,
        taxes_amount_cents: 262,
        taxes_rate: 10.0,
        precise_coupons_amount_cents: 379.41176
      )
      expect(sub2_fees.where(charge: {billable_metric_id: bm8.id}).first).to have_attributes(
        amount_cents: 4_000,
        taxes_amount_cents: 349,
        taxes_rate: 10.0,
        precise_coupons_amount_cents: 505.88235
      )

      expect(invoice.fees_amount_cents).to eq(20_000)
      expect(invoice.coupons_amount_cents).to eq(3_500)
      expect(invoice.sub_total_excluding_taxes_amount_cents).to eq(16_500)
      expect(invoice.taxes_amount_cents).to eq(1_889)
      expect(invoice.total_amount_cents).to eq(18_389)
    end
  end

  context "when progressive billing and multiple subscriptions with multiple invoices" do
    context "when coupon is single use" do
      it "applies the coupon only once, calculating the remaining amount" do
        # Create billable metric
        create_metric(name: "Name", code: "bm1", aggregation_type: "sum_agg", field_name: "total1")
        bm = organization.billable_metrics.find_by(code: "bm1")

        # Create plan with pay_in_advance charge
        create_plan(
          {
            name: "Pay in Advance Plan",
            code: "pay_in_advance_plan",
            interval: "monthly",
            amount_cents: 0,
            amount_currency: "EUR",
            pay_in_advance: false,
            charges: [
              {
                billable_metric_id: bm.id,
                charge_model: "standard",
                pay_in_advance: true,
                properties: {amount: "1"}
              }
            ]
          }
        )
        pay_in_advance_plan = organization.plans.find_by(code: "pay_in_advance_plan")

        # Create plan with progressive billing
        create_plan(
          {
            name: "Progressive Billing Plan",
            code: "progressive_plan",
            interval: "monthly",
            amount_cents: 20_00, # $20
            amount_currency: "EUR",
            pay_in_advance: false,
            charges: [
              {
                billable_metric_id: bm.id,
                charge_model: "standard",
                pay_in_advance: false,
                properties: {amount: "14"} # $14 per unit
              }
            ],
            usage_thresholds: [
              {
                amount_cents: 20_00, # $20 threshold
                threshold_display_name: "First threshold"
              },
              {
                amount_cents: 50_00, # $50 threshold
                threshold_display_name: "Second threshold"
              }
            ]
          }
        )
        progressive_plan = organization.plans.find_by(code: "progressive_plan")

        # Create single use coupon
        create_coupon(
          {
            name: "Single Use Coupon",
            code: "single_use_coupon",
            coupon_type: "fixed_amount",
            frequency: "once",
            amount_cents: 100_00, # $100
            amount_currency: "EUR",
            expiration: "time_limit",
            expiration_at: Time.current + 50.days,
            reusable: false
          }
        )

        # Create customer and subscriptions
        create_or_update_customer(external_id: "customer-12345")
        customer = organization.customers.find_by(external_id: "customer-12345")

        # Apply coupon to customer
        apply_coupon({external_customer_id: "customer-12345", coupon_code: "single_use_coupon"})

        # Start subscriptions 1 month ago (time0)
        time0 = DateTime.new(2025, 1, 1)
        travel_to(time0) do
          # Create pay in advance subscription
          create_subscription(
            {
              external_customer_id: "customer-12345",
              external_id: "sub_pay_in_advance",
              plan_code: pay_in_advance_plan.code
            }
          )

          # Create progressive billing subscription
          create_subscription(
            {
              external_customer_id: "customer-12345",
              external_id: "sub_progressive",
              plan_code: progressive_plan.code
            }
          )
        end

        # time0 + 5 days: send an event (5 units)
        travel_to(time0 + 5.days) do
          create_event(
            {
              code: bm.code,
              transaction_id: SecureRandom.uuid,
              external_subscription_id: "sub_pay_in_advance",
              properties: {total1: 5}
            }
          )

          # Check that invoice is generated for pay_in_advance and coupon is applied
          pay_in_advance_subscription = Subscription.find_by(external_id: "sub_pay_in_advance")
          expect(pay_in_advance_subscription.fees.count).to eq(1)

          fee = pay_in_advance_subscription.fees.first
          expect(fee.amount_cents).to eq(5_00) # 5 units * $1 = $5
          expect(fee.pay_in_advance).to eq(true)

          # Check that coupon was applied to the pay in advance invoice
          invoice = pay_in_advance_subscription.invoices.first
          expect(invoice).to be_present
          expect(invoice.coupons_amount_cents).to eq(5_00) # Coupon applied to the $5 fee
        end

        # time0 + 10 days: send event (5 units) and perform lifetime calculation
        travel_to(time0 + 10.days) do
          create_event(
            {
              code: bm.code,
              transaction_id: SecureRandom.uuid,
              external_subscription_id: "sub_progressive",
              properties: {total1: 5}
            }
          )

          # Perform lifetime calculation to trigger progressive billing
          perform_usage_update

          # Check that 2 invoices are generated - progressive billing and pay in advance
          progressive_subscription = Subscription.find_by(external_id: "sub_progressive")
          pay_in_advance_subscription = Subscription.find_by(external_id: "sub_pay_in_advance")

          # Progressive billing should have triggered an invoice
          progressive_invoices = progressive_subscription.invoices
          expect(progressive_invoices.count).to eq(1)

          progressive_invoice = progressive_invoices.first
          expect(progressive_invoice.invoice_type).to eq("progressive_billing")
          # 5 units * $14 = $70, but threshold is $20, so should invoice $20
          expect(progressive_invoice.total_amount_cents).to eq(20_00)

          # Pay in advance should have another invoice
          pay_in_advance_invoices = pay_in_advance_subscription.invoices
          expect(pay_in_advance_invoices.count).to eq(2) # Original + new one
        end

        # time0 + 15 days: send an event (5 units)
        travel_to(time0 + 15.days) do
          create_event(
            {
              code: bm.code,
              transaction_id: SecureRandom.uuid,
              external_subscription_id: "sub_pay_in_advance",
              properties: {total1: 5}
            }
          )

          # Check that invoice is generated for pay_in_advance and coupon is applied
          pay_in_advance_subscription = Subscription.find_by(external_id: "sub_pay_in_advance")
          expect(pay_in_advance_subscription.fees.count).to eq(3) # 2 previous + 1 new

          latest_fee = pay_in_advance_subscription.fees.order(:created_at).last
          expect(latest_fee.amount_cents).to eq(5_00) # 5 units * $1 = $5
          expect(latest_fee.pay_in_advance).to eq(true)
        end

        # Travel to time0 + 1 month, run subscription billing
        travel_to(time0 + 1.month) do
          perform_billing

          # Check that one invoice is generated with two subscriptions
          customer = organization.customers.find_by(external_id: "customer-12345")
          expect(customer.invoices.count).to be > 0

          # Check that coupon was applied correctly across all invoices
          total_coupon_amount = customer.invoices.sum(:coupons_amount_cents)
          expect(total_coupon_amount).to eq(100_00) # Total coupon amount should be $100
        end

        # Repeat for next month
        time1 = time0 + 1.month
        travel_to(time1 + 5.days) do
          create_event(
            {
              code: bm.code,
              transaction_id: SecureRandom.uuid,
              external_subscription_id: "sub_pay_in_advance",
              properties: {total1: 5}
            }
          )

          # Check that no coupon is applied since it's single use
          pay_in_advance_subscription = Subscription.find_by(external_id: "sub_pay_in_advance")
          latest_invoice = pay_in_advance_subscription.invoices.order(:created_at).last
          expect(latest_invoice.coupons_amount_cents).to eq(0) # No coupon applied
        end

        travel_to(time1 + 10.days) do
          create_event(
            {
              code: bm.code,
              transaction_id: SecureRandom.uuid,
              external_subscription_id: "sub_progressive",
              properties: {total1: 5}
            }
          )

          perform_usage_update

          # Check progressive billing still works without coupon
          progressive_subscription = Subscription.find_by(external_id: "sub_progressive")
          progressive_invoices = progressive_subscription.invoices
          expect(progressive_invoices.count).to be > 0
        end

        travel_to(time1 + 15.days) do
          create_event(
            {
              code: bm.code,
              transaction_id: SecureRandom.uuid,
              external_subscription_id: "sub_pay_in_advance",
              properties: {total1: 5}
            }
          )

          # Check no coupon applied
          pay_in_advance_subscription = Subscription.find_by(external_id: "sub_pay_in_advance")
          latest_invoice = pay_in_advance_subscription.invoices.order(:created_at).last
          expect(latest_invoice.coupons_amount_cents).to eq(0)
        end

        travel_to(time1 + 1.month) do
          perform_billing

          # Verify no coupon is applied in the second month
          customer = organization.customers.find_by(external_id: "customer-12345")
          second_month_invoices = customer.invoices.where("created_at >= ?", time1)
          total_coupon_amount = second_month_invoices.sum(:coupons_amount_cents)
          expect(total_coupon_amount).to eq(0) # No coupon in second month
        end
      end
    end
  end
end
