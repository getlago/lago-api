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
      it "applies the coupon, calculating the remaining amount", transaction: false do
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
                properties: {amount: "1"} # $1 per unit
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
            expiration: "no_expiration",
            reusable: false
          }
        )

        # Create customer and subscriptions
        create_or_update_customer(external_id: "customer-12345")
        customer = organization.customers.find_by(external_id: "customer-12345")

        # Apply coupon to customer
        apply_coupon({external_customer_id: "customer-12345", coupon_code: "single_use_coupon"})

        # Start subscriptions at time0
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
          pay_in_advance_subscription = Subscription.find_by(external_id: "sub_pay_in_advance")
          progressive_subscription = Subscription.find_by(external_id: "sub_progressive")
          ingest_event(pay_in_advance_subscription, bm, 5)
          ingest_event(progressive_subscription, bm, 10)

          # Check that invoice is generated for pay_in_advance
          expect(pay_in_advance_subscription.invoices.count).to eq(1)

          fee = pay_in_advance_subscription.fees.first
          expect(fee.amount_cents).to eq(5_00) # 5 units * $1 = $5
          expect(fee.pay_in_advance).to eq(true)

          # Check that coupon was applied to the pay in advance invoice (coupons are applied to pay-in-advance)
          invoice = pay_in_advance_subscription.invoices.first
          expect(invoice).to be_present
          expect(invoice.coupons_amount_cents).to eq(5_00) # Coupons are applied on pay in advance invoices
          expect(invoice.fees_amount_cents).to eq(5_00)
          expect(invoice.total_amount_cents).to eq(0)
          expect(progressive_subscription.invoices.count).to eq(0)
          perform_all_enqueued_jobs
        end

        # time0 + 10 days: send event (5 units) and perform lifetime calculation
        travel_to(time0 + 10.days) do
          pay_in_advance_subscription = Subscription.find_by(external_id: "sub_pay_in_advance")
          progressive_subscription = Subscription.find_by(external_id: "sub_progressive")
          ingest_event(pay_in_advance_subscription, bm, 5)
          ingest_event(progressive_subscription, bm, 10)

          # Check that progressive billing invoice is generated
          # At time0 + 5 days: 10 units = $10 (does NOT exceed $20 threshold)
          # At time0 + 10 days: 10 more units = $20 total (exceeds $20 threshold)
          progressive_invoices = progressive_subscription.invoices
          expect(progressive_invoices.count).to eq(1) # 1 progressive billing invoice

          # Invoice should be for $20 (total usage at threshold)
          progressive_invoice = progressive_invoices.first
          expect(progressive_invoice.fees_amount_cents).to eq(20_00)
          expect(progressive_invoice.coupons_amount_cents).to eq(20_00) # 20 units - 20$ coupon = 0
          expect(progressive_invoice.total_amount_cents).to eq(0) # 20 units - 20$ coupon = 0

          # Pay in advance should have another invoice
          pay_in_advance_invoices = pay_in_advance_subscription.invoices
          expect(pay_in_advance_invoices.count).to eq(2) # Original + new one
        end

        # time0 + 15 days: send an event (5 units)
        travel_to(time0 + 15.days) do
          pay_in_advance_subscription = Subscription.find_by(external_id: "sub_pay_in_advance")
          progressive_subscription = Subscription.find_by(external_id: "sub_progressive")
          ingest_event(pay_in_advance_subscription, bm, 5)
          ingest_event(progressive_subscription, bm, 10)

          # Check that invoice is generated for pay_in_advance
          expect(pay_in_advance_subscription.fees.count).to eq(3) # 2 previous + 1 new
          expect(progressive_subscription.fees.count).to eq(1) # 1 progressive billing fee

          latest_fee = pay_in_advance_subscription.fees.order(:created_at).last
          expect(latest_fee.amount_cents).to eq(5_00) # 5 units * $1 = $5
          expect(latest_fee.pay_in_advance).to eq(true) # Pay in advance
        end

        # Travel to time0 + 1 month, run subscription billing
        # coupon usage: 20$ progressive usage + 30$ subscription invoice + 3 * 5$ pay in advance invoice = 65$
        travel_to(time0 + 1.month) do
          perform_billing

          # Check that invoices are generated
          customer = organization.customers.find_by(external_id: "customer-12345")
          expect(customer.invoices.count).to eq(5) # 3 pay in advance + 1 progressive_billing + 1 subscription
          progressive_subscription = Subscription.find_by(external_id: "sub_progressive")
          subscription_invoice = progressive_subscription.invoices.order(:created_at).last
          expect(subscription_invoice.fees_amount_cents).to eq(50_00) # 30 units * $1 = $30 + subscription fee 20$
          expect(subscription_invoice.progressive_billing_credit_amount_cents).to eq(20_00)
          expect(subscription_invoice.coupons_amount_cents).to eq(30_00)
          expect(subscription_invoice.total_amount_cents).to eq(0)
        end
        # coupon remaining: 35$

        # Repeat for next month
        time1 = time0 + 1.month
        travel_to(time1 + 5.days) do
          pay_in_advance_subscription = Subscription.find_by(external_id: "sub_pay_in_advance")
          progressive_subscription = Subscription.find_by(external_id: "sub_progressive")
          ingest_event(pay_in_advance_subscription, bm, 5)
          ingest_event(progressive_subscription, bm, 10)

          # Check that invoice is generated for pay_in_advance
          expect(pay_in_advance_subscription.invoices.count).to eq(5) # 4 previous (3 pay in advance + 1 subscription) + 1 new (5 units)

          fee = pay_in_advance_subscription.fees.order(:created_at).last
          expect(fee.amount_cents).to eq(5_00) # 5 units * $1 = $5
          expect(fee.pay_in_advance).to eq(true)

          # Check that no coupon is applied since it's single use
          invoice = pay_in_advance_subscription.invoices.order(:created_at).last
          expect(invoice).to be_present
          expect(invoice.fees_amount_cents).to eq(5_00)
          expect(invoice.coupons_amount_cents).to eq(5_00) # 5$ coupon applied
          expect(invoice.total_amount_cents).to eq(0)
          expect(progressive_subscription.invoices.count).to eq(2) # 2 previous + 0 new (no threshold exceeded)
          perform_all_enqueued_jobs
        end

        travel_to(time1 + 10.days) do
          pay_in_advance_subscription = Subscription.find_by(external_id: "sub_pay_in_advance")
          progressive_subscription = Subscription.find_by(external_id: "sub_progressive")
          ingest_event(pay_in_advance_subscription, bm, 5)
          ingest_event(progressive_subscription, bm, 10)

          # Check that progressive billing invoice is generated
          # At time1 + 5 days: 10 units = $10 (does NOT exceed $20 threshold)
          # At time1 + 10 days: 10 more units = $20 total (exceeds $20 threshold)
          progressive_invoices = progressive_subscription.invoices
          expect(progressive_invoices.count).to eq(3) # 2 previous + 1 new

          # Invoice should be for $20 (total usage at threshold)
          progressive_invoice = progressive_invoices.order(:created_at).last
          expect(progressive_invoice.fees_amount_cents).to eq(20_00)
          expect(progressive_invoice.coupons_amount_cents).to eq(20_00) # 20 units - 20$ coupon = 0
          expect(progressive_invoice.total_amount_cents).to eq(0) # 20 units - 20$ coupon = 0

          # Pay in advance should have another invoice
          pay_in_advance_invoices = pay_in_advance_subscription.invoices
          expect(pay_in_advance_invoices.count).to eq(6) # 5 previous (4 pay in advance + 1 subscription) + 1 new (5 units)
        end

        # coupon remaining: 5$
        travel_to(time1 + 1.month) do
          perform_billing

          # Check that invoices are generated
          customer = organization.customers.find_by(external_id: "customer-12345")
          # Pay in advance: 3 prev month + 2 this month
          # Progressive billing: 1 prev month + 1 this month
          # Subscription: 1 prev month + 1 this month (combines both subscriptions through invoice_subscriptions)
          expect(customer.invoices.count).to eq(9) # 5 previous + 3 pay in advance + 1 progressive_billing + 1 subscription
          progressive_subscription = Subscription.find_by(external_id: "sub_progressive")
          subscription_invoice = progressive_subscription.invoices.order(:created_at).last
          expect(subscription_invoice.fees_amount_cents).to eq(40_00) # 20 units * $1 = $20 + subscription fee 20$
          expect(subscription_invoice.progressive_billing_credit_amount_cents).to eq(20_00)
          expect(subscription_invoice.coupons_amount_cents).to eq(5_00) # 5$ coupon applied
          expect(subscription_invoice.total_amount_cents).to eq(15_00) # 40$ - 20$ credit - 5$ coupon = 15$
        end
      end
    end

    context "when coupon is recurring" do
      context "when recurring once" do
        it "applies the coupon only during one billing period, calculating the remaining amount", transaction: false do
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
                  properties: {amount: "1"} # $1 per unit
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

          # Create recurring coupon with frequency equal 1 month
          create_coupon(
            {
              name: "Single Use Coupon",
              code: "single_use_coupon",
              coupon_type: "fixed_amount",
              frequency: "recurring",
              frequency_duration: 1,
              amount_cents: 100_00, # $100
              amount_currency: "EUR",
              expiration: "no_expiration",
              reusable: false
            }
          )

          # Create customer and subscriptions
          create_or_update_customer(external_id: "customer-12345")
          customer = organization.customers.find_by(external_id: "customer-12345")

          # Apply coupon to customer
          apply_coupon({external_customer_id: "customer-12345", coupon_code: "single_use_coupon"})

          # Start subscriptions at time0
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
            pay_in_advance_subscription = Subscription.find_by(external_id: "sub_pay_in_advance")
            progressive_subscription = Subscription.find_by(external_id: "sub_progressive")
            ingest_event(pay_in_advance_subscription, bm, 5)
            ingest_event(progressive_subscription, bm, 10)

            # Check that invoice is generated for pay_in_advance
            expect(pay_in_advance_subscription.invoices.count).to eq(1)

            fee = pay_in_advance_subscription.fees.first
            expect(fee.amount_cents).to eq(5_00) # 5 units * $1 = $5
            expect(fee.pay_in_advance).to eq(true)

            # Check that coupon was applied to the pay in advance invoice (coupons are applied to pay-in-advance)
            invoice = pay_in_advance_subscription.invoices.first
            expect(invoice).to be_present
            expect(invoice.coupons_amount_cents).to eq(5_00) # Coupons are applied on pay in advance invoices
            expect(invoice.fees_amount_cents).to eq(5_00)
            expect(invoice.total_amount_cents).to eq(0)
            expect(progressive_subscription.invoices.count).to eq(0)
            perform_all_enqueued_jobs
          end

          # time0 + 10 days: send event (5 units) and perform lifetime calculation
          travel_to(time0 + 10.days) do
            pay_in_advance_subscription = Subscription.find_by(external_id: "sub_pay_in_advance")
            progressive_subscription = Subscription.find_by(external_id: "sub_progressive")
            ingest_event(pay_in_advance_subscription, bm, 5)
            ingest_event(progressive_subscription, bm, 10)

            # Check that progressive billing invoice is generated
            # At time0 + 5 days: 10 units = $10 (does NOT exceed $20 threshold)
            # At time0 + 10 days: 10 more units = $20 total (exceeds $20 threshold)
            progressive_invoices = progressive_subscription.invoices
            expect(progressive_invoices.count).to eq(1) # 1 progressive billing invoice

            # Invoice should be for $20 (total usage at threshold)
            progressive_invoice = progressive_invoices.first
            expect(progressive_invoice.fees_amount_cents).to eq(20_00)
            expect(progressive_invoice.coupons_amount_cents).to eq(20_00) # 20 units - 20$ coupon = 0
            expect(progressive_invoice.total_amount_cents).to eq(0) # 20 units - 20$ coupon = 0

            # Pay in advance should have another invoice
            pay_in_advance_invoices = pay_in_advance_subscription.invoices
            expect(pay_in_advance_invoices.count).to eq(2) # Original + new one
          end

          # time0 + 15 days: send an event (5 units)
          travel_to(time0 + 15.days) do
            pay_in_advance_subscription = Subscription.find_by(external_id: "sub_pay_in_advance")
            progressive_subscription = Subscription.find_by(external_id: "sub_progressive")
            ingest_event(pay_in_advance_subscription, bm, 5)
            ingest_event(progressive_subscription, bm, 10)

            # Check that invoice is generated for pay_in_advance
            expect(pay_in_advance_subscription.fees.count).to eq(3) # 2 previous + 1 new
            expect(progressive_subscription.fees.count).to eq(1) # 1 progressive billing fee

            latest_fee = pay_in_advance_subscription.fees.order(:created_at).last
            expect(latest_fee.amount_cents).to eq(5_00) # 5 units * $1 = $5
            expect(latest_fee.pay_in_advance).to eq(true) # Pay in advance
          end

          # Travel to time0 + 1 month, run subscription billing
          # coupon usage: 20$ progressive usage + 30$ subscription invoice + 3 * 5$ pay in advance invoice = 65$
          travel_to(time0 + 1.month) do
            perform_billing

            # Check that invoices are generated
            customer = organization.customers.find_by(external_id: "customer-12345")
            expect(customer.invoices.count).to eq(5) # 3 pay in advance + 1 progressive_billing + 1 subscription
            progressive_subscription = Subscription.find_by(external_id: "sub_progressive")
            subscription_invoice = progressive_subscription.invoices.order(:created_at).last
            expect(subscription_invoice.fees_amount_cents).to eq(50_00) # 30 units * $1 = $30 + subscription fee 20$
            expect(subscription_invoice.progressive_billing_credit_amount_cents).to eq(20_00)
            expect(subscription_invoice.coupons_amount_cents).to eq(30_00)
            expect(subscription_invoice.total_amount_cents).to eq(0)
          end
          # coupon remaining: 35$
          # coupon is terminated

          # Repeat for next month
          time1 = time0 + 1.month
          travel_to(time1 + 5.days) do
            pay_in_advance_subscription = Subscription.find_by(external_id: "sub_pay_in_advance")
            progressive_subscription = Subscription.find_by(external_id: "sub_progressive")
            ingest_event(pay_in_advance_subscription, bm, 5)
            ingest_event(progressive_subscription, bm, 10)

            # Check that invoice is generated for pay_in_advance
            expect(pay_in_advance_subscription.invoices.count).to eq(5) # 4 previous (3 pay in advance + 1 subscription) + 1 new (5 units)

            fee = pay_in_advance_subscription.fees.order(:created_at).last
            expect(fee.amount_cents).to eq(5_00) # 5 units * $1 = $5
            expect(fee.pay_in_advance).to eq(true)

            # Check that no coupon is applied since it's single use
            invoice = pay_in_advance_subscription.invoices.order(:created_at).last
            expect(invoice).to be_present
            expect(invoice.fees_amount_cents).to eq(5_00)
            expect(invoice.coupons_amount_cents).to eq(0)
            expect(invoice.total_amount_cents).to eq(5_00)
            expect(progressive_subscription.invoices.count).to eq(2) # 2 previous + 0 new (no threshold exceeded)
            perform_all_enqueued_jobs
          end

          travel_to(time1 + 10.days) do
            pay_in_advance_subscription = Subscription.find_by(external_id: "sub_pay_in_advance")
            progressive_subscription = Subscription.find_by(external_id: "sub_progressive")
            ingest_event(pay_in_advance_subscription, bm, 5)
            ingest_event(progressive_subscription, bm, 10)

            # Check that progressive billing invoice is generated
            # At time1 + 5 days: 10 units = $10 (does NOT exceed $20 threshold)
            # At time1 + 10 days: 10 more units = $20 total (exceeds $20 threshold)
            progressive_invoices = progressive_subscription.invoices
            expect(progressive_invoices.count).to eq(3) # 2 previous + 1 new

            # Invoice should be for $20 (total usage at threshold)
            progressive_invoice = progressive_invoices.order(:created_at).last
            expect(progressive_invoice.fees_amount_cents).to eq(20_00)
            expect(progressive_invoice.coupons_amount_cents).to eq(0)
            expect(progressive_invoice.total_amount_cents).to eq(20_00) # 20 units - 20$ coupon = 0

            # Pay in advance should have another invoice
            pay_in_advance_invoices = pay_in_advance_subscription.invoices
            expect(pay_in_advance_invoices.count).to eq(6) # 5 previous (4 pay in advance + 1 subscription) + 1 new (5 units)
          end

          # coupon remaining: 5$
          travel_to(time1 + 1.month) do
            perform_billing

            # Check that invoices are generated
            customer = organization.customers.find_by(external_id: "customer-12345")
            # Pay in advance: 3 prev month + 2 this month
            # Progressive billing: 1 prev month + 1 this month
            # Subscription: 1 prev month + 1 this month (combines both subscriptions through invoice_subscriptions)
            expect(customer.invoices.count).to eq(9) # 5 previous + 3 pay in advance + 1 progressive_billing + 1 subscription
            progressive_subscription = Subscription.find_by(external_id: "sub_progressive")
            subscription_invoice = progressive_subscription.invoices.order(:created_at).last
            expect(subscription_invoice.fees_amount_cents).to eq(40_00) # 20 units * $1 = $20 + subscription fee 20$
            expect(subscription_invoice.progressive_billing_credit_amount_cents).to eq(20_00)
            expect(subscription_invoice.coupons_amount_cents).to eq(0)
            expect(subscription_invoice.total_amount_cents).to eq(20_00) # 20$ - 20$ credit = 20$
          end
        end

        it "does not terminate if nothing was billed" do
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

          create_coupon(
            {
              name: "Recurring Coupon",
              code: "recurring_coupon",
              coupon_type: "fixed_amount",
              frequency: "recurring",
              frequency_duration: 1,
              amount_cents: 100_00, # $100
              amount_currency: "EUR",
              expiration: "no_expiration",
              reusable: false
            }
          )

          create_or_update_customer(external_id: "customer-12345")
          customer = organization.customers.find_by(external_id: "customer-12345")

          # Apply coupon to customer
          apply_coupon({external_customer_id: "customer-12345", coupon_code: "recurring_coupon"})

          # Start subscription at time0
          time0 = DateTime.new(2025, 1, 1)
          travel_to(time0) do
            # Create subscription
            create_subscription(
              {
                external_customer_id: "customer-12345",
                external_id: "sub_pay_in_advance",
                plan_code: pay_in_advance_plan.code
              }
            )
          end

          travel_to(time0 + 1.month) do
            perform_billing

            pay_in_advance_subscription = Subscription.find_by(external_id: "sub_pay_in_advance")

            # Check that invoice is generated for pay in advance
            expect(pay_in_advance_subscription.invoices.count).to eq(1)
            expect(customer.applied_coupons.first.frequency_duration_remaining).to eq(1)
            expect(customer.applied_coupons.first.status).to eq("active")
          end
        end
      end

      context "when recurring multiple times" do
        it "applies the coupon multiple times, calculating the remaining amount", transaction: false do
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
                  properties: {amount: "1"} # $1 per unit
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

          # Create recurring coupon with frequency equal 3 months
          create_coupon(
            {
              name: "Recurring Coupon",
              code: "recurring_coupon",
              coupon_type: "fixed_amount",
              frequency: "recurring",
              frequency_duration: 3,
              amount_cents: 100_00, # $100
              amount_currency: "EUR",
              expiration: "no_expiration",
              reusable: false
            }
          )

          # Create customer and subscriptions
          create_or_update_customer(external_id: "customer-12345")
          customer = organization.customers.find_by(external_id: "customer-12345")

          # Apply coupon to customer
          apply_coupon({external_customer_id: "customer-12345", coupon_code: "recurring_coupon"})

          # Start subscriptions at time0
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

          # time0 + 5 days: send events (5 units for pay in advance, 10 units for progressive billing)
          travel_to(time0 + 5.days) do
            pay_in_advance_subscription = Subscription.find_by(external_id: "sub_pay_in_advance")
            progressive_subscription = Subscription.find_by(external_id: "sub_progressive")
            ingest_event(pay_in_advance_subscription, bm, 5)
            ingest_event(progressive_subscription, bm, 10)

            # Check that invoice is generated for pay_in_advance
            expect(pay_in_advance_subscription.invoices.count).to eq(1)

            fee = pay_in_advance_subscription.fees.first
            expect(fee.amount_cents).to eq(5_00) # 5 units * $1 = $5
            expect(fee.pay_in_advance).to eq(true)

            # Check that coupon was applied to the pay in advance invoice
            invoice = pay_in_advance_subscription.invoices.first
            expect(invoice).to be_present
            expect(invoice.coupons_amount_cents).to eq(5_00) # Coupons are applied on pay in advance invoices
            expect(invoice.fees_amount_cents).to eq(5_00)
            expect(invoice.total_amount_cents).to eq(0)
            expect(progressive_subscription.invoices.count).to eq(0)
            perform_all_enqueued_jobs
          end

          # time0 + 10 days: send events (5 units for pay in advance, 10 units for progressive billing)
          travel_to(time0 + 10.days) do
            pay_in_advance_subscription = Subscription.find_by(external_id: "sub_pay_in_advance")
            progressive_subscription = Subscription.find_by(external_id: "sub_progressive")
            ingest_event(pay_in_advance_subscription, bm, 5)
            ingest_event(progressive_subscription, bm, 10)

            # Check that progressive billing invoice is generated
            progressive_invoices = progressive_subscription.invoices
            expect(progressive_invoices.count).to eq(1) # 1 progressive billing invoice

            # Invoice should be for $20 (total usage at threshold)
            progressive_invoice = progressive_invoices.first
            expect(progressive_invoice.fees_amount_cents).to eq(20_00)
            expect(progressive_invoice.coupons_amount_cents).to eq(20_00) # 20 units - 20$ coupon = 0
            expect(progressive_invoice.total_amount_cents).to eq(0) # 20 units - 20$ coupon = 0

            # Pay in advance should have another invoice
            pay_in_advance_invoices = pay_in_advance_subscription.invoices
            expect(pay_in_advance_invoices.count).to eq(2) # Original + new one
          end

          # time0 + 15 days: send an event (5 units)
          travel_to(time0 + 15.days) do
            pay_in_advance_subscription = Subscription.find_by(external_id: "sub_pay_in_advance")
            progressive_subscription = Subscription.find_by(external_id: "sub_progressive")
            ingest_event(pay_in_advance_subscription, bm, 5)
            ingest_event(progressive_subscription, bm, 10)

            # Check that invoice is generated for pay_in_advance
            expect(pay_in_advance_subscription.fees.count).to eq(3) # 2 previous + 1 new
            expect(progressive_subscription.fees.count).to eq(1) # 1 progressive billing fee

            latest_fee = pay_in_advance_subscription.fees.order(:created_at).last
            expect(latest_fee.amount_cents).to eq(5_00) # 5 units * $1 = $5
            expect(latest_fee.pay_in_advance).to eq(true) # Pay in advance
          end

          # Travel to time0 + 1 month, run subscription billing
          # coupon usage after billing: 20$ progressive usage + 30$ subscription invoice + 3 * 5$ pay in advance invoice = 65$
          travel_to(time0 + 1.month) do
            perform_billing

            # Check that invoices are generated
            customer = organization.customers.find_by(external_id: "customer-12345")
            expect(customer.invoices.count).to eq(5) # 3 pay in advance + 1 progressive_billing + 1 subscription
            progressive_subscription = Subscription.find_by(external_id: "sub_progressive")
            subscription_invoice = progressive_subscription.invoices.order(:created_at).last
            expect(subscription_invoice.fees_amount_cents).to eq(50_00) # 30 units * $1 = $30 + subscription fee 20$
            expect(subscription_invoice.progressive_billing_credit_amount_cents).to eq(20_00)
            expect(subscription_invoice.coupons_amount_cents).to eq(30_00)
            expect(subscription_invoice.total_amount_cents).to eq(0)
            expect(customer.applied_coupons.first.frequency_duration_remaining).to eq(2)
          end

          # Second month
          time1 = time0 + 1.month
          travel_to(time1 + 5.days) do
            pay_in_advance_subscription = Subscription.find_by(external_id: "sub_pay_in_advance")
            progressive_subscription = Subscription.find_by(external_id: "sub_progressive")
            ingest_event(pay_in_advance_subscription, bm, 5)
            ingest_event(progressive_subscription, bm, 10)

            # Check that invoice is generated for pay_in_advance
            expect(pay_in_advance_subscription.invoices.count).to eq(5) # 4 previous (3 pay in advance + 1 subscription) + 1 new (5 units)

            fee = pay_in_advance_subscription.fees.order(:created_at).last
            expect(fee.amount_cents).to eq(5_00) # 5 units * $1 = $5
            expect(fee.pay_in_advance).to eq(true)

            # Check that coupon is still applied since it's recurring for 3 months
            invoice = pay_in_advance_subscription.invoices.order(:created_at).last
            expect(invoice).to be_present
            expect(invoice.fees_amount_cents).to eq(5_00)
            expect(invoice.coupons_amount_cents).to eq(5_00) # 5$ coupon applied
            expect(invoice.total_amount_cents).to eq(0)
            expect(progressive_subscription.invoices.count).to eq(2) # 2 previous + 0 new (no threshold exceeded)
            perform_all_enqueued_jobs
          end

          travel_to(time1 + 10.days) do
            pay_in_advance_subscription = Subscription.find_by(external_id: "sub_pay_in_advance")
            progressive_subscription = Subscription.find_by(external_id: "sub_progressive")
            ingest_event(pay_in_advance_subscription, bm, 5)
            ingest_event(progressive_subscription, bm, 10)

            # Check that progressive billing invoice is generated
            progressive_invoices = progressive_subscription.invoices
            expect(progressive_invoices.count).to eq(3) # 2 previous + 1 new

            # Invoice should be for $20 (total usage at threshold)
            progressive_invoice = progressive_invoices.order(:created_at).last
            expect(progressive_invoice.fees_amount_cents).to eq(20_00)
            expect(progressive_invoice.coupons_amount_cents).to eq(20_00) # 20$ coupon applied
            expect(progressive_invoice.total_amount_cents).to eq(0) # 20 units - 20$ coupon = 0

            # Pay in advance should have another invoice
            pay_in_advance_invoices = pay_in_advance_subscription.invoices
            expect(pay_in_advance_invoices.count).to eq(6) # 5 previous (4 pay in advance + 1 subscription) + 1 new (5 units)
          end

          # coupon still active for 1 more billing period
          travel_to(time1 + 1.month) do
            perform_billing

            # Check that invoices are generated
            customer = organization.customers.find_by(external_id: "customer-12345")
            expect(customer.invoices.count).to eq(9) # 5 previous + 3 pay in advance + 1 progressive_billing + 1 subscription
            progressive_subscription = Subscription.find_by(external_id: "sub_progressive")
            subscription_invoice = progressive_subscription.invoices.order(:created_at).last
            expect(subscription_invoice.fees_amount_cents).to eq(40_00) # 20 units * $1 = $20 + subscription fee 20$
            expect(subscription_invoice.progressive_billing_credit_amount_cents).to eq(20_00)
            expect(subscription_invoice.coupons_amount_cents).to eq(20_00) # 20$ coupon applied
            expect(subscription_invoice.total_amount_cents).to eq(0) # 40$ - 20$ credit - 20$ coupon = 0
            expect(customer.applied_coupons.first.frequency_duration_remaining).to eq(1)
          end

          # Third month, last coupon cycle
          time2 = time0 + 2.months
          travel_to(time2 + 5.days) do
            pay_in_advance_subscription = Subscription.find_by(external_id: "sub_pay_in_advance")
            progressive_subscription = Subscription.find_by(external_id: "sub_progressive")
            ingest_event(pay_in_advance_subscription, bm, 5)
            ingest_event(progressive_subscription, bm, 10)

            # Check that invoice is generated for pay_in_advance
            expect(pay_in_advance_subscription.invoices.count).to eq(8) # 7 previous + 1 new (5 units)

            fee = pay_in_advance_subscription.fees.order(:created_at).last
            expect(fee.amount_cents).to eq(5_00) # 5 units * $1 = $5
            expect(fee.pay_in_advance).to eq(true)

            # Check that coupon is still applied since it's recurring for 3 months
            invoice = pay_in_advance_subscription.invoices.order(:created_at).last
            expect(invoice).to be_present
            expect(invoice.fees_amount_cents).to eq(5_00)
            expect(invoice.coupons_amount_cents).to eq(5_00) # 5$ coupon applied
            expect(invoice.total_amount_cents).to eq(0)
            expect(progressive_subscription.invoices.count).to eq(4) # 3 previous + 0 new (no threshold exceeded)
            perform_all_enqueued_jobs
          end

          travel_to(time2 + 10.days) do
            pay_in_advance_subscription = Subscription.find_by(external_id: "sub_pay_in_advance")
            progressive_subscription = Subscription.find_by(external_id: "sub_progressive")
            ingest_event(pay_in_advance_subscription, bm, 5)
            ingest_event(progressive_subscription, bm, 10)

            # Check that progressive billing invoice is not generated
            progressive_invoices = progressive_subscription.invoices
            expect(progressive_invoices.count).to eq(4) # 4 previous

            # Pay in advance should have another invoice
            pay_in_advance_invoices = pay_in_advance_subscription.invoices
            expect(pay_in_advance_invoices.count).to eq(9) # 8 previous + 1 new (5 units)
            expect(customer.applied_coupons.first.frequency_duration_remaining).to eq(1)
            expect(customer.applied_coupons.first.status).to eq("active")

            terminate_subscription(progressive_subscription)
            perform_all_enqueued_jobs
            expect(customer.applied_coupons.first.frequency_duration_remaining).to eq(0)
            expect(customer.applied_coupons.first.status).to eq("terminated")
          end

          # check that coupon is no longer applied
          travel_to(time2 + 15.days) do
            pay_in_advance_subscription = Subscription.find_by(external_id: "sub_pay_in_advance")
            ingest_event(pay_in_advance_subscription, bm, 5)

            # Check that pay in advance invoice is generated
            pay_in_advance_invoices = pay_in_advance_subscription.invoices.order(:created_at)
            expect(pay_in_advance_invoices.count).to eq(10) # 9 previous + 1 new (5 units)
            expect(pay_in_advance_invoices.last.fees_amount_cents).to eq(5_00) # 5 units * $1 = $5
            expect(pay_in_advance_invoices.last.coupons_amount_cents).to eq(0) # 0$ coupon applied
            expect(pay_in_advance_invoices.last.total_amount_cents).to eq(5_00) # 5$ - 0$ coupon = 5$
          end
        end
      end

      context "when recurring forever" do
        it "applies the coupon multiple times, calculating the remaining amount", transaction: false do
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
                  properties: {amount: "1"} # $1 per unit
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
                },
                {
                  amount_cents: 80_00, # $80 threshold
                  threshold_display_name: "Second threshold"
                }
              ]
            }
          )
          progressive_plan = organization.plans.find_by(code: "progressive_plan")

          # Create recurring coupon with frequency forever (nil frequency_duration)
          create_coupon(
            {
              name: "Forever Recurring Coupon",
              code: "forever_recurring_coupon",
              coupon_type: "fixed_amount",
              frequency: "forever",
              frequency_duration: nil, # Forever
              amount_cents: 50_00,
              amount_currency: "EUR",
              expiration: "no_expiration",
              reusable: false
            }
          )

          # Create customer and subscriptions
          create_or_update_customer(external_id: "customer-12345")
          customer = organization.customers.find_by(external_id: "customer-12345")

          # Apply coupon to customer
          apply_coupon({external_customer_id: "customer-12345", coupon_code: "forever_recurring_coupon"})

          # Start subscriptions at time0
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

          # time0 + 5 days: send events (5 units for pay in advance, 10 units for progressive billing)
          travel_to(time0 + 5.days) do
            pay_in_advance_subscription = Subscription.find_by(external_id: "sub_pay_in_advance")
            progressive_subscription = Subscription.find_by(external_id: "sub_progressive")
            ingest_event(pay_in_advance_subscription, bm, 5)
            ingest_event(progressive_subscription, bm, 10)

            # Check that invoice is generated for pay_in_advance
            expect(pay_in_advance_subscription.invoices.count).to eq(1)

            fee = pay_in_advance_subscription.fees.first
            expect(fee.amount_cents).to eq(5_00) # 5 units * $1 = $5
            expect(fee.pay_in_advance).to eq(true)

            # Check that coupon was applied to the pay in advance invoice
            invoice = pay_in_advance_subscription.invoices.first
            expect(invoice).to be_present
            expect(invoice.coupons_amount_cents).to eq(5_00) # Coupons are applied on pay in advance invoices
            expect(invoice.fees_amount_cents).to eq(5_00)
            expect(invoice.total_amount_cents).to eq(0)
            expect(progressive_subscription.invoices.count).to eq(0)
            perform_all_enqueued_jobs
          end

          # time0 + 10 days: send events (5 units for pay in advance, 10 units for progressive billing)
          travel_to(time0 + 10.days) do
            pay_in_advance_subscription = Subscription.find_by(external_id: "sub_pay_in_advance")
            progressive_subscription = Subscription.find_by(external_id: "sub_progressive")
            ingest_event(pay_in_advance_subscription, bm, 5)
            ingest_event(progressive_subscription, bm, 10)

            # Check that progressive billing invoice is generated
            progressive_invoices = progressive_subscription.invoices
            expect(progressive_invoices.count).to eq(1) # 1 progressive billing invoice

            # Invoice should be for $20 (total usage at threshold)
            progressive_invoice = progressive_invoices.first
            expect(progressive_invoice.fees_amount_cents).to eq(20_00)
            expect(progressive_invoice.coupons_amount_cents).to eq(20_00) # 20 units - 20$ coupon = 0
            expect(progressive_invoice.total_amount_cents).to eq(0) # 20 units - 20$ coupon = 0

            # Pay in advance should have another invoice
            pay_in_advance_invoices = pay_in_advance_subscription.invoices
            expect(pay_in_advance_invoices.count).to eq(2) # Original + new one
          end

          # time0 + 15 days: send an event (5 units)
          travel_to(time0 + 15.days) do
            pay_in_advance_subscription = Subscription.find_by(external_id: "sub_pay_in_advance")
            progressive_subscription = Subscription.find_by(external_id: "sub_progressive")
            ingest_event(pay_in_advance_subscription, bm, 5)
            ingest_event(progressive_subscription, bm, 10)

            # Check that invoice is generated for pay_in_advance
            expect(pay_in_advance_subscription.fees.count).to eq(3) # 2 previous + 1 new
            expect(progressive_subscription.fees.count).to eq(1) # 1 progressive billing fee

            latest_fee = pay_in_advance_subscription.fees.order(:created_at).last
            expect(latest_fee.amount_cents).to eq(5_00) # 5 units * $1 = $5
            expect(latest_fee.pay_in_advance).to eq(true) # Pay in advance
          end

          # Travel to time0 + 1 month, run subscription billing
          # when applied forever, coupons are applied by subscription
          # coupon usage after billing: 20$ progressive usage + 30$ subscription invoice; 3 * 5$ pay in advance invoice
          travel_to(time0 + 1.month) do
            perform_billing

            # Check that invoices are generated
            customer = organization.customers.find_by(external_id: "customer-12345")
            expect(customer.invoices.count).to eq(5) # 3 pay in advance + 1 progressive_billing + 1 subscription
            progressive_subscription = Subscription.find_by(external_id: "sub_progressive")
            subscription_invoice = progressive_subscription.invoices.order(:created_at).last
            expect(subscription_invoice.fees_amount_cents).to eq(50_00) # 30 units * $1 = $30 + subscription fee 20$
            expect(subscription_invoice.progressive_billing_credit_amount_cents).to eq(20_00)
            expect(subscription_invoice.coupons_amount_cents).to eq(30_00)
            expect(subscription_invoice.total_amount_cents).to eq(0)
            expect(customer.applied_coupons.first.frequency_duration_remaining).to eq(nil) # Forever
            expect(customer.applied_coupons.first.status).to eq("active")
          end

          # Second month - coupon is fully available again
          time1 = time0 + 1.month
          travel_to(time1 + 5.days) do
            pay_in_advance_subscription = Subscription.find_by(external_id: "sub_pay_in_advance")
            progressive_subscription = Subscription.find_by(external_id: "sub_progressive")
            ingest_event(pay_in_advance_subscription, bm, 30)
            ingest_event(progressive_subscription, bm, 10)

            # Check that invoice is generated for pay_in_advance
            expect(pay_in_advance_subscription.invoices.count).to eq(5) # 4 previous (3 pay in advance + 1 subscription) + 1 new (5 units)

            fee = pay_in_advance_subscription.fees.order(:created_at).last
            expect(fee.amount_cents).to eq(30_00) # 30 units * $1 = $30
            expect(fee.pay_in_advance).to eq(true)

            # Check that coupon is still applied since it's recurring forever
            invoice = pay_in_advance_subscription.invoices.order(:created_at).last
            expect(invoice).to be_present
            expect(invoice.fees_amount_cents).to eq(30_00)
            expect(invoice.coupons_amount_cents).to eq(30_00) # 30$ coupon applied
            expect(invoice.total_amount_cents).to eq(0)
            expect(progressive_subscription.invoices.count).to eq(2) # 2 previous + 0 new (no threshold exceeded)
            perform_all_enqueued_jobs
          end

          travel_to(time1 + 10.days) do
            pay_in_advance_subscription = Subscription.find_by(external_id: "sub_pay_in_advance")
            progressive_subscription = Subscription.find_by(external_id: "sub_progressive")
            ingest_event(pay_in_advance_subscription, bm, 30)
            ingest_event(progressive_subscription, bm, 20)

            # Pay in advance should have another invoice
            pay_in_advance_invoices = pay_in_advance_subscription.invoices.order(:created_at)
            expect(pay_in_advance_invoices.count).to eq(6) # 5 previous (4 pay in advance + 1 subscription) + 1 new (30 units)
            expect(pay_in_advance_invoices.last.fees_amount_cents).to eq(30_00) # 30 units * $1 = $30
            expect(pay_in_advance_invoices.last.coupons_amount_cents).to eq(20_00) # 20$ coupon remaining
            expect(pay_in_advance_invoices.last.total_amount_cents).to eq(10_00) # 30$ - 20$ coupon = 10$

            # Check that progressive billing invoice is generated
            progressive_invoices = progressive_subscription.invoices
            expect(progressive_invoices.count).to eq(3) # 2 previous + 1 new

            # Invoice should be for $30 (total usage at threshold); this is 50$ threshold (total usage now is 60$)
            progressive_invoice = progressive_invoices.order(:created_at).last
            expect(progressive_invoice.fees_amount_cents).to eq(30_00)
            expect(progressive_invoice.coupons_amount_cents).to eq(30_00) # 30$ coupon applied
            expect(progressive_invoice.total_amount_cents).to eq(0) # 30 units - 30$ coupon = 0
          end

          # coupon usage so far: 30$ + 30$; 30$
          travel_to(time1 + 15.days) do
            pay_in_advance_subscription = Subscription.find_by(external_id: "sub_pay_in_advance")
            progressive_subscription = Subscription.find_by(external_id: "sub_progressive")
            ingest_event(pay_in_advance_subscription, bm, 20)
            ingest_event(progressive_subscription, bm, 50)

            # Check that progressive billing invoice is generated again
            progressive_invoices = progressive_subscription.invoices
            expect(progressive_invoices.count).to eq(4) # 3 previous + 1 new

            # Invoice should be for $80 (total usage is 110, 20 is invoiced in previous billing period - is not used in calculation,
            # 30 is progressively billed in this period, so it is calculated
            # when applied forever, coupons are applied by subscription
            progressive_invoice = progressive_invoices.order(:created_at).last
            expect(progressive_invoice.fees_amount_cents).to eq(80_00)
            expect(progressive_invoice.coupons_amount_cents).to eq(20_00) # only 20$ of coupon is remaining
            expect(progressive_invoice.progressive_billing_credit_amount_cents).to eq(30_00)
            expect(progressive_invoice.total_amount_cents).to eq(30_00) # 50 units - 20$ coupon = 30$

            # Pay in advance should have another invoice
            pay_in_advance_invoices = pay_in_advance_subscription.invoices
            expect(pay_in_advance_invoices.count).to eq(7) # 6 previous (5 pay in advance + 1 subscription) + 1 new (30 units)
          end

          # coupon still active forever
          travel_to(time1 + 1.month) do
            perform_billing

            # Check that invoices are generated
            customer = organization.customers.find_by(external_id: "customer-12345")
            expect(customer.invoices.count).to eq(11) # 5 previous + 3 pay in advance + 2 progressive_billing + 1 subscription
            progressive_subscription = Subscription.find_by(external_id: "sub_progressive")
            subscription_invoice = progressive_subscription.invoices.order(:created_at).last
            expect(subscription_invoice.fees_amount_cents).to eq(100_00) # 80 units * $1 = $80 + subscription fee 20$
            expect(subscription_invoice.progressive_billing_credit_amount_cents).to eq(80_00)
            expect(subscription_invoice.coupons_amount_cents).to eq(0) # current coupon is fully used
            expect(subscription_invoice.total_amount_cents).to eq(20_00) # 100$ - 80$ credit = 20$
            expect(customer.applied_coupons.first.frequency_duration_remaining).to eq(nil) # Forever
            expect(customer.applied_coupons.first.status).to eq("active")
          end

          # Third month - coupon should still be active forever
          time2 = time0 + 2.months
          travel_to(time2 + 5.days) do
            pay_in_advance_subscription = Subscription.find_by(external_id: "sub_pay_in_advance")
            progressive_subscription = Subscription.find_by(external_id: "sub_progressive")
            ingest_event(pay_in_advance_subscription, bm, 5)
            ingest_event(progressive_subscription, bm, 10)

            # Check that invoice is generated for pay_in_advance
            expect(pay_in_advance_subscription.invoices.count).to eq(9) # 8 previous + 1 new (5 units)

            fee = pay_in_advance_subscription.fees.order(:created_at).last
            expect(fee.amount_cents).to eq(5_00) # 5 units * $1 = $5
            expect(fee.pay_in_advance).to eq(true)

            # Check that coupon is still applied since it's recurring forever
            invoice = pay_in_advance_subscription.invoices.order(:created_at).last
            expect(invoice).to be_present
            expect(invoice.fees_amount_cents).to eq(5_00)
            expect(invoice.coupons_amount_cents).to eq(5_00) # 5$ coupon applied
            expect(invoice.total_amount_cents).to eq(0)
            expect(progressive_subscription.invoices.count).to eq(5) # 5 previous + 0 new (no threshold exceeded)
            perform_all_enqueued_jobs
          end

          travel_to(time2 + 10.days) do
            pay_in_advance_subscription = Subscription.find_by(external_id: "sub_pay_in_advance")
            progressive_subscription = Subscription.find_by(external_id: "sub_progressive")
            ingest_event(pay_in_advance_subscription, bm, 5)
            ingest_event(progressive_subscription, bm, 10)

            # Check that progressive billing invoice is not generated, because all thresholds are exceeded
            progressive_invoices = progressive_subscription.invoices
            expect(progressive_invoices.count).to eq(5) # 5 previous

            # Pay in advance should have another invoice
            pay_in_advance_invoices = pay_in_advance_subscription.invoices
            expect(pay_in_advance_invoices.count).to eq(10) # 9 previous + 1 new (5 units)

            terminate_subscription(progressive_subscription)
            perform_all_enqueued_jobs
            expect(customer.applied_coupons.first.frequency_duration_remaining).to eq(nil) # Still forever
            expect(customer.applied_coupons.first.status).to eq("active")
          end

          # check that coupon is still applied after subscription termination
          travel_to(time2 + 15.days) do
            pay_in_advance_subscription = Subscription.find_by(external_id: "sub_pay_in_advance")
            ingest_event(pay_in_advance_subscription, bm, 5)

            # Check that pay in advance invoice is generated
            pay_in_advance_invoices = pay_in_advance_subscription.invoices.order(:created_at)
            expect(pay_in_advance_invoices.count).to eq(11) # 10 previous + 1 new (5 units)
            expect(pay_in_advance_invoices.last.fees_amount_cents).to eq(5_00) # 5 units * $1 = $5
            expect(pay_in_advance_invoices.last.coupons_amount_cents).to eq(5_00) # 5$ coupon applied
            expect(pay_in_advance_invoices.last.total_amount_cents).to eq(0) # 5$ - 5$ coupon = 0
          end
        end
      end
    end
  end
end
