# frozen_string_literal: true

require "rails_helper"

describe "Progressive billing invoices", :premium, transaction: false do
  let(:organization) { create(:organization, webhook_url: nil, email_settings: [], premium_integrations: ["progressive_billing"]) }
  let(:billing_entity) { create(:billing_entity, organization:) }
  let(:plan) { create(:plan, organization: organization, interval: "monthly", amount_cents: 31_00, pay_in_advance: false) }
  let(:upgrade_plan) { create(:plan, organization: organization, interval: "monthly", amount_cents: 62_000, pay_in_advance: false) }
  let(:downgrade_plan) { create(:plan, organization: organization, interval: "monthly", amount_cents: 31, pay_in_advance: false) }
  let(:customer) { create(:customer, organization:, billing_entity:, invoice_grace_period:) }
  let(:billable_metric) { create(:billable_metric, organization: organization, field_name: "total", aggregation_type: "sum_agg") }
  let(:charge) { create(:charge, plan: plan, billable_metric: billable_metric, charge_model: "standard", properties: {"amount" => "0.0002"}) }
  let(:usage_threshold) { create(:usage_threshold, plan: plan, amount_cents: 20000) }
  let(:usage_threshold2) { create(:usage_threshold, plan: plan, amount_cents: 50000) }
  let(:invoice_grace_period) { nil }

  before do
    usage_threshold
    charge
  end

  it "generates an invoice in the middle of the month and a final invoice at the end of the month" do
    time_0 = DateTime.new(2022, 12, 1)
    travel_to time_0 do
      create_subscription(
        {
          external_customer_id: customer.external_id,
          external_id: customer.external_id,
          plan_code: plan.code
        }
      )
    end
    subscription = customer.subscriptions.first

    travel_to time_0 + 5.days do
      ingest_event(subscription, billable_metric, 1000000)
      expect(Invoice.count).to eq(1)
      expect(Invoice.last.total_amount_cents).to eq(20000)
    end

    travel_to time_0 + 15.days do
      ingest_event(subscription, billable_metric, 1000000)
      expect(Invoice.count).to eq(1)
      progressive_billing_invoice = subscription.invoices.first
      expect(progressive_billing_invoice.total_amount_cents).to eq(20000)
    end

    travel_to time_0 + 1.month do
      perform_billing
      expect(Invoice.count).to eq(2)
      recurring_invoice = subscription.invoices.order(:created_at).last
      expect(recurring_invoice.total_amount_cents).to eq(31_00 + 20_000)
      expect(recurring_invoice.fees_amount_cents).to eq(31_00 + 40_000)
      expect(recurring_invoice.progressive_billing_credit_amount_cents).to eq(20_000)
    end
  end

  context "with a percentage coupon limited to metrics and a fixed coupon" do
    let(:plan) { create(:plan, organization:, interval: "monthly", amount_cents: 0, pay_in_advance: false) }
    let(:charge) { create(:standard_charge, plan:, billable_metric:, properties: {amount: "0.01"}) }
    let(:usage_threshold) { create(:usage_threshold, plan:, amount_cents: 10_339) }
    let(:additional_progressive_invoice) { false }
    let(:expected_progressive_amounts) { [1169] }
    let(:expected_final_amount) { 209 }

    before do
      coupon = create(:coupon, organization:, coupon_type: "percentage", percentage_rate: 50,
        frequency: "recurring", frequency_duration: 12, limited_billable_metrics: true)
      create(:coupon_target, organization:, coupon:, billable_metric:)
      create(:applied_coupon, customer:, coupon:, percentage_rate: 50,
        frequency: "recurring", frequency_duration: 12, frequency_duration_remaining: 12)
      fixed_coupon = create(:coupon, organization:, amount_cents: 4000, frequency: "forever")
      create(:applied_coupon, customer:, coupon: fixed_coupon, amount_cents: 4000, frequency: "forever")
    end

    shared_examples "a discounted billing period" do
      it "discounts the full period before deducting the net progressive credit" do
        start_time = Time.zone.parse("2026-08-01")
        travel_to(start_time) do
          create_subscription({external_customer_id: customer.external_id,
                               external_id: customer.external_id, plan_code: plan.code})
        end
        subscription = customer.subscriptions.sole

        travel_to(start_time + 5.days) { ingest_event(subscription, billable_metric, 10_339) }
        if additional_progressive_invoice
          travel_to(start_time + 10.days) { ingest_event(subscription, billable_metric, 161) }
          travel_to(start_time + 15.days) { ingest_event(subscription, billable_metric, 256) }
        else
          travel_to(start_time + 15.days) { ingest_event(subscription, billable_metric, 417) }
        end

        progressive_invoices = subscription.invoices.progressive_billing.order(:created_at)
        expect(progressive_invoices.pluck(:total_amount_cents)).to eq(expected_progressive_amounts)

        travel_to(start_time + 1.month) do
          perform_billing
          invoice = subscription.invoices.subscription.sole

          expect(invoice.fees_amount_cents).to eq(10_756)
          expect(invoice.coupons_amount_cents).to eq(9378)
          expect(invoice.total_amount_cents).to eq(expected_final_amount)
          expect(invoice.fees.sum(&:sub_total_excluding_taxes_amount_cents)).to eq(expected_final_amount)
          expect(progressive_invoices.sum(:total_amount_cents) + invoice.total_amount_cents).to eq(1378)
        end
      end
    end

    include_examples "a discounted billing period"

    context "with two progressive invoices" do
      let(:additional_progressive_invoice) { true }
      let(:expected_progressive_amounts) { [1169, 81] }
      let(:expected_final_amount) { 128 }

      before { create(:usage_threshold, plan:, amount_cents: 10_500) }

      include_examples "a discounted billing period"
    end
  end

  context "with grace period enabled" do
    let(:invoice_grace_period) { 2 }

    it "generates an invoice in the middle of the month and a draft invoice at the end of the month" do
      time_0 = DateTime.new(2022, 12, 1)
      travel_to time_0 do
        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: customer.external_id,
            plan_code: plan.code
          }
        )
      end
      subscription = customer.subscriptions.first

      travel_to time_0 + 5.days do
        ingest_event(subscription, billable_metric, 1000000)
        expect(Invoice.count).to eq(1)
        expect(Invoice.last.total_amount_cents).to eq(20000)
      end

      travel_to time_0 + 15.days do
        ingest_event(subscription, billable_metric, 1000000)
        expect(Invoice.count).to eq(1)
        progressive_billing_invoice = subscription.invoices.first
        expect(progressive_billing_invoice.total_amount_cents).to eq(20000)
      end

      travel_to time_0 + 1.month do
        perform_billing
        expect(Invoice.count).to eq(2)
        recurring_invoice = subscription.invoices.order(:created_at).last
        expect(recurring_invoice).to be_draft
        expect(recurring_invoice.total_amount_cents).to eq(31_00 + 20_000)
        expect(recurring_invoice.fees_amount_cents).to eq(31_00 + 40_000)
        expect(recurring_invoice.progressive_billing_credit_amount_cents).to eq(20_000)

        refresh_invoice(recurring_invoice)
        expect(recurring_invoice).to be_draft
        expect(recurring_invoice.total_amount_cents).to eq(31_00 + 20_000)
        expect(recurring_invoice.fees_amount_cents).to eq(31_00 + 40_000)
        expect(recurring_invoice.progressive_billing_credit_amount_cents).to eq(20_000)
      end
    end
  end

  it "generates an invoice in the middle of the month and terminates the subscription before the end of the month" do
    time_0 = DateTime.new(2022, 12, 1)
    travel_to time_0 do
      create_subscription(
        {
          external_customer_id: customer.external_id,
          external_id: customer.external_id,
          plan_code: plan.code
        }
      )
    end
    subscription = customer.subscriptions.first

    travel_to time_0 + 15.days do
      ingest_event(subscription, billable_metric, 1000000)
      expect(Invoice.count).to eq(1)
      expect(Invoice.last.total_amount_cents).to eq(20000)
    end

    travel_to time_0 + 17.days do
      terminate_subscription(subscription)
      expect(Invoice.count).to eq(2)
      termination_invoice = subscription.invoices.order(:created_at).last
      expect(termination_invoice.total_amount_cents).to eq(1800)
      expect(termination_invoice.fees_amount_cents).to eq(21800)
      expect(termination_invoice.progressive_billing_credit_amount_cents).to eq(20000)
    end
  end

  it "generates an invoice in the middle of the month and upgrades the subscription before the end of the month" do
    time_0 = DateTime.new(2022, 12, 1)
    travel_to time_0 do
      create_subscription(
        {
          external_customer_id: customer.external_id,
          external_id: customer.external_id,
          plan_code: plan.code
        }
      )
    end
    subscription = customer.subscriptions.first

    travel_to time_0 + 15.days do
      ingest_event(subscription, billable_metric, 1000000)
      expect(Invoice.count).to eq(1)
      expect(Invoice.last.total_amount_cents).to eq(20000)
    end

    travel_to time_0 + 17.days do
      create_subscription(
        {
          external_customer_id: customer.external_id,
          external_id: customer.external_id,
          plan_code: upgrade_plan.code
        }
      )
      expect(Invoice.count).to eq(2)
      termination_invoice = subscription.invoices.order(:created_at).last
      expect(termination_invoice.total_amount_cents).to eq(1700)
      expect(termination_invoice.fees_amount_cents).to eq(21700)
      expect(termination_invoice.progressive_billing_credit_amount_cents).to eq(20000)
    end
  end

  it "generates an invoice during the grace period and finalizes it at the end of the next month" do
    billing_entity.update!(invoice_grace_period: 30)
    time_0 = DateTime.new(2022, 12, 1)
    travel_to time_0 do
      create_subscription(
        {
          external_customer_id: customer.external_id,
          external_id: customer.external_id,
          plan_code: plan.code
        }
      )
    end
    subscription = customer.subscriptions.first

    travel_to time_0 + 1.month + 2.hours do
      perform_billing
      expect(Invoice.count).to eq(1)
      subscription_invoice_1 = subscription.invoices.first
      expect(subscription_invoice_1.total_amount_cents).to eq(31_00)
      expect(subscription_invoice_1.progressive_billing_credit_amount_cents).to eq(0)
      expect(subscription_invoice_1.status).to eq("draft")
    end

    travel_to time_0 + 1.month + 15.days do
      ingest_event(subscription, billable_metric, 3000000)
      expect(Invoice.count).to eq(2)
      progressive_invoice = subscription.invoices.order(:created_at).last
      expect(progressive_invoice.total_amount_cents).to eq(60000)
    end

    travel_to time_0 + 2.months do
      perform_finalize_refresh
      perform_billing
      expect(Invoice.count).to eq(3)
      expect(CreditNote.count).to eq(0)
      subscription_invoice_1 = subscription.invoices.order(:created_at).subscription.first
      expect(subscription_invoice_1.total_amount_cents).to eq(31_00)
      expect(subscription_invoice_1.progressive_billing_credit_amount_cents).to eq(0)
      expect(subscription_invoice_1.status).to eq("finalized")
      expect(subscription_invoice_1.fees_amount_cents).to eq(31_00)

      subscription_invoice_2 = subscription.invoices.order(:created_at).subscription.last
      expect(subscription_invoice_2.total_amount_cents).to eq(3100)
      expect(subscription_invoice_2.progressive_billing_credit_amount_cents).to eq(60000)
      expect(subscription_invoice_2.status).to eq("draft")
      expect(subscription_invoice_2.fees_amount_cents).to eq(631_00)
    end
  end

  it "generates invoices for multiple usage thresholds within the same billing period" do
    usage_threshold2
    time_0 = DateTime.new(2022, 12, 1)
    travel_to time_0 do
      create_subscription(
        {
          external_customer_id: customer.external_id,
          external_id: customer.external_id,
          plan_code: plan.code
        }
      )
    end
    subscription = customer.subscriptions.first

    travel_to time_0 + 15.days do
      ingest_event(subscription, billable_metric, 1000000)
      expect(Invoice.count).to eq(1)
      expect(subscription.invoices.order(:created_at).last.total_amount_cents).to eq(20000)
    end

    travel_to time_0 + 20.days do
      ingest_event(subscription, billable_metric, 1000000)
      expect(Invoice.count).to eq(1)
    end

    travel_to time_0 + 25.days do
      ingest_event(subscription, billable_metric, 1000000)
      expect(Invoice.count).to eq(2)
      expect(subscription.invoices.order(:created_at).last.total_amount_cents).to eq(40000)
    end

    travel_to time_0 + 1.month do
      perform_billing
      expect(Invoice.count).to eq(3)
      subscription_invoice = subscription.invoices.subscription.last
      expect(subscription_invoice.total_amount_cents).to eq(31_00)
      expect(subscription_invoice.progressive_billing_credit_amount_cents).to eq(60000)
    end
  end

  it "generates only the final invoice at the end of the month" do
    time_0 = Time.current.beginning_of_month
    travel_to time_0 do
      create_subscription(
        {
          external_customer_id: customer.external_id,
          external_id: customer.external_id,
          plan_code: plan.code
        }
      )
    end
    subscription = customer.subscriptions.first

    travel_to time_0 + 1.month do
      perform_billing
      expect(Invoice.count).to eq(1)
      expect(subscription.invoices.subscription.first.total_amount_cents).to eq(31_00)
    end
  end

  it "generates progressive billing invoices only once when not recurring" do
    time_0 = DateTime.new(2022, 12, 1)
    travel_to time_0 do
      create_subscription(
        {
          external_customer_id: customer.external_id,
          external_id: customer.external_id,
          plan_code: plan.code
        }
      )
    end
    subscription = customer.subscriptions.first

    # First billing period
    travel_to time_0 + 15.days do
      ingest_event(subscription, billable_metric, 1000000)
      expect(Invoice.count).to eq(1)
      expect(subscription.invoices.order(:created_at).last.total_amount_cents).to eq(20000)
    end

    travel_to time_0 + 1.month do
      perform_billing
      expect(Invoice.count).to eq(2)
      expect(subscription.invoices.order(:created_at).last.total_amount_cents).to eq(31_00)
      expect(subscription.invoices.order(:created_at).last.fees_amount_cents).to eq(31_00 + 20000)
    end

    # Second billing period
    travel_to time_0 + 1.month + 15.days do
      ingest_event(subscription, billable_metric, 2000000)
      expect(Invoice.count).to eq(2)
    end

    travel_to time_0 + 2.months do
      perform_billing
      expect(Invoice.count).to eq(3)
      expect(subscription.invoices.order(:created_at).last.total_amount_cents).to eq(431_00)
    end

    # Third billing period
    travel_to time_0 + 2.months + 15.days do
      ingest_event(subscription, billable_metric, 3000000)
      expect(Invoice.count).to eq(3)
    end

    travel_to time_0 + 3.months do
      perform_billing
      expect(Invoice.count).to eq(4)
      expect(subscription.invoices.order(:created_at).last.total_amount_cents).to eq(631_00)
    end
  end

  it "generates correct invoices when there is a combination of single thresholds and recurring" do
    usage_threshold.update(amount_cents: 200)
    create(:usage_threshold, plan: plan, amount_cents: 500)
    create(:usage_threshold, plan: plan, amount_cents: 700)
    create(:usage_threshold, plan: plan, amount_cents: 1000, recurring: true)
    date_0 = DateTime.new(2022, 12, 1)
    travel_to date_0 do
      create_subscription(
        {
          external_customer_id: customer.external_id,
          external_id: customer.external_id,
          plan_code: plan.code
        }
      )
    end
    subscription = customer.subscriptions.first

    # First billing period
    travel_to date_0 + 5.days do
      ingest_event(subscription, billable_metric, 11000)
      expect(Invoice.count).to eq(1)
      expect(subscription.invoices.order(:created_at).last.total_amount_cents).to eq(220)
    end

    travel_to date_0 + 10.days do
      ingest_event(subscription, billable_metric, 11000)
      expect(Invoice.count).to eq(1)
    end

    travel_to date_0 + 15.days do
      ingest_event(subscription, billable_metric, 11000)
      expect(Invoice.count).to eq(2)
      expect(subscription.invoices.order(:created_at).last.total_amount_cents).to eq(440)
    end

    travel_to date_0 + 20.days do
      ingest_event(subscription, billable_metric, 11000)
      expect(Invoice.count).to eq(3)
      expect(subscription.invoices.order(:created_at).last.total_amount_cents).to eq(220)
    end

    travel_to date_0 + 25.days do
      ingest_event(subscription, billable_metric, 110000)
      expect(Invoice.count).to eq(4)
      expect(subscription.invoices.order(:created_at).last.total_amount_cents).to eq(2200)
    end

    travel_to date_0 + 27.days do
      ingest_event(subscription, billable_metric, 110000)
      expect(Invoice.count).to eq(5)
      expect(subscription.invoices.order(:created_at).last.total_amount_cents).to eq(2200)
    end

    # second billing period
    travel_to date_0 + 1.month do
      perform_billing
      expect(Invoice.count).to eq(6)
      expect(subscription.invoices.order(:created_at).last.total_amount_cents).to eq(3100)
      expect(subscription.invoices.order(:created_at).last.progressive_billing_credit_amount_cents).to eq(5280)
    end

    travel_to date_0 + 1.month + 5.days do
      ingest_event(subscription, billable_metric, 110000)
      expect(Invoice.count).to eq(7)
      expect(subscription.invoices.order(:created_at).last.total_amount_cents).to eq(2200)
    end
  end
end
