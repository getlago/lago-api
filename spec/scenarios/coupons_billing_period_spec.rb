# frozen_string_literal: true

require "rails_helper"

describe "Coupons billing period", :premium, transaction: false do
  let(:organization) { create(:organization, webhook_url: nil, premium_integrations: ["progressive_billing"]) }
  let(:start_time) { Time.zone.parse("2025-01-01") }
  let(:billable_metric) { create(:sum_billable_metric, organization:, field_name: "units") }
  let(:in_advance_billable_metric) { create(:sum_billable_metric, organization:, field_name: "units") }
  let(:add_on) { create(:add_on, organization:) }
  let(:in_arrears_add_on) { create(:add_on, organization:) }
  let(:subscription) { organization.subscriptions.find_by(external_id: "sub") }

  let(:plan_amount_cents) { 0 }
  let(:plan_pay_in_advance) { false }
  let(:charges) { [] }
  let(:fixed_charges) { [] }
  let(:plan_options) { {} }
  let(:coupon_amount_cents) { 15_00 }

  before do
    create_plan({
      name: "Plan", code: "plan", interval: "monthly", amount_currency: "EUR",
      amount_cents: plan_amount_cents, pay_in_advance: plan_pay_in_advance, charges:, fixed_charges:, **plan_options
    })
    create_coupon({
      name: "Forever", code: "forever", coupon_type: "fixed_amount", frequency: "forever",
      amount_cents: coupon_amount_cents, amount_currency: "EUR", expiration: "no_expiration", reusable: false
    })
    create_or_update_customer({external_id: "cust", currency: "EUR"})
    apply_coupon({external_customer_id: "cust", coupon_code: "forever"})

    travel_to(start_time) do
      create_subscription({external_customer_id: "cust", external_id: "sub", plan_code: "plan", billing_time: "calendar"})
    end
  end

  def month(number)
    Date.new(2025, number, 1)..Date.new(2025, number, 1).end_of_month
  end

  def bill_on(date)
    travel_to(date.in_time_zone) { perform_billing }
  end

  def ingest_on(date, units, metric = billable_metric)
    travel_to(date.in_time_zone + 10.hours) { ingest_event(subscription, metric, units) }
  end

  def service_period(fee)
    keys = {
      "subscription" => %w[from_datetime to_datetime],
      "commitment" => %w[from_datetime to_datetime],
      "charge" => %w[charges_from_datetime charges_to_datetime],
      "fixed_charge" => %w[fixed_charges_from_datetime fixed_charges_to_datetime]
    }.fetch(fee.fee_type)

    from, to = fee.properties.values_at(*keys).map { |value| Time.zone.parse(value.to_s).to_date }
    from..to
  end

  def billed_invoices
    subscription.invoices.order(:created_at).map do |invoice|
      {
        issued: invoice.issuing_date,
        reason: invoice.invoice_subscriptions.sole.invoicing_reason,
        fees: invoice.fees.map { |fee| [fee.fee_type, fee.amount_cents, service_period(fee)] }.sort,
        coupon: invoice.coupons_amount_cents
      }
    end
  end

  context "with a subscription fee only" do
    let(:plan_amount_cents) { 10_00 }

    context "when the subscription is paid in advance" do
      let(:plan_pay_in_advance) { true }

      it "caps the coupon on each billed month" do
        bill_on(Date.new(2025, 2, 1))
        bill_on(Date.new(2025, 3, 1))

        expect(billed_invoices).to eq([
          {issued: Date.new(2025, 1, 1), reason: "subscription_starting", fees: [["subscription", 10_00, month(1)]], coupon: 10_00},
          {issued: Date.new(2025, 2, 1), reason: "subscription_periodic", fees: [["subscription", 10_00, month(2)]], coupon: 10_00},
          {issued: Date.new(2025, 3, 1), reason: "subscription_periodic", fees: [["subscription", 10_00, month(3)]], coupon: 10_00}
        ])
      end
    end

    context "when the subscription is paid in arrears" do
      it "caps the coupon on each billed month" do
        bill_on(Date.new(2025, 2, 1))
        bill_on(Date.new(2025, 3, 1))

        expect(billed_invoices).to eq([
          {issued: Date.new(2025, 2, 1), reason: "subscription_periodic", fees: [["subscription", 10_00, month(1)]], coupon: 10_00},
          {issued: Date.new(2025, 3, 1), reason: "subscription_periodic", fees: [["subscription", 10_00, month(2)]], coupon: 10_00}
        ])
      end
    end
  end

  context "with charges only" do
    let(:charge_pay_in_advance) { false }
    let(:charges) do
      [{billable_metric_id: billable_metric.id, charge_model: "standard", pay_in_advance: charge_pay_in_advance, properties: {amount: "1"}}]
    end

    context "when charges are paid in advance" do
      let(:charge_pay_in_advance) { true }

      it "caps the coupon across the pay-in-advance invoices of each month" do
        ingest_on(Date.new(2025, 1, 10), 10)
        ingest_on(Date.new(2025, 1, 20), 10)
        bill_on(Date.new(2025, 2, 1))
        ingest_on(Date.new(2025, 2, 10), 10)
        ingest_on(Date.new(2025, 2, 20), 10)
        bill_on(Date.new(2025, 3, 1))

        expect(billed_invoices).to eq([
          {issued: Date.new(2025, 1, 10), reason: "in_advance_charge", fees: [["charge", 10_00, month(1)]], coupon: 10_00},
          {issued: Date.new(2025, 1, 20), reason: "in_advance_charge", fees: [["charge", 10_00, month(1)]], coupon: 5_00},
          {issued: Date.new(2025, 2, 1), reason: "subscription_periodic", fees: [["subscription", 0, month(1)]], coupon: 0},
          {issued: Date.new(2025, 2, 10), reason: "in_advance_charge", fees: [["charge", 10_00, month(2)]], coupon: 10_00},
          {issued: Date.new(2025, 2, 20), reason: "in_advance_charge", fees: [["charge", 10_00, month(2)]], coupon: 5_00},
          {issued: Date.new(2025, 3, 1), reason: "subscription_periodic", fees: [["subscription", 0, month(2)]], coupon: 0}
        ])
      end
    end

    context "when charges are paid in arrears" do
      it "caps the coupon on each billed month" do
        ingest_on(Date.new(2025, 1, 10), 20)
        bill_on(Date.new(2025, 2, 1))
        ingest_on(Date.new(2025, 2, 10), 20)
        bill_on(Date.new(2025, 3, 1))

        expect(billed_invoices).to eq([
          {issued: Date.new(2025, 2, 1), reason: "subscription_periodic", fees: [["charge", 20_00, month(1)], ["subscription", 0, month(1)]], coupon: 15_00},
          {issued: Date.new(2025, 3, 1), reason: "subscription_periodic", fees: [["charge", 20_00, month(2)], ["subscription", 0, month(2)]], coupon: 15_00}
        ])
      end
    end
  end

  context "with fixed charges only" do
    let(:fixed_charge_pay_in_advance) { false }
    let(:fixed_charges) do
      [{add_on_id: add_on.id, charge_model: "standard", units: 1, pay_in_advance: fixed_charge_pay_in_advance, prorated: false, properties: {amount: "10"}}]
    end

    context "when fixed charges are paid in advance" do
      let(:fixed_charge_pay_in_advance) { true }

      it "caps the coupon across the fixed charge invoices of each month" do
        travel_to(Time.zone.parse("2025-01-15 10:00")) do
          fixed_charge = organization.plans.find_by(code: "plan").fixed_charges.sole
          update_plan(subscription.plan, {
            fixed_charges: [{id: fixed_charge.id, units: 2, apply_units_immediately: true, charge_model: "standard", properties: {amount: "10"}}]
          })
          perform_all_enqueued_jobs
        end
        bill_on(Date.new(2025, 2, 1))
        bill_on(Date.new(2025, 3, 1))

        expect(billed_invoices).to eq([
          {issued: Date.new(2025, 1, 1), reason: "in_advance_charge", fees: [["fixed_charge", 10_00, month(1)]], coupon: 10_00},
          {issued: Date.new(2025, 1, 15), reason: "in_advance_charge", fees: [["fixed_charge", 10_00, month(1)]], coupon: 5_00},
          {issued: Date.new(2025, 2, 1), reason: "subscription_periodic", fees: [["fixed_charge", 20_00, month(2)], ["subscription", 0, month(1)]], coupon: 15_00},
          {issued: Date.new(2025, 3, 1), reason: "subscription_periodic", fees: [["fixed_charge", 20_00, month(3)], ["subscription", 0, month(2)]], coupon: 15_00}
        ])
      end
    end

    context "when fixed charges are paid in arrears" do
      it "caps the coupon on each billed month" do
        bill_on(Date.new(2025, 2, 1))
        bill_on(Date.new(2025, 3, 1))

        expect(billed_invoices).to eq([
          {issued: Date.new(2025, 2, 1), reason: "subscription_periodic", fees: [["fixed_charge", 10_00, month(1)], ["subscription", 0, month(1)]], coupon: 10_00},
          {issued: Date.new(2025, 3, 1), reason: "subscription_periodic", fees: [["fixed_charge", 10_00, month(2)], ["subscription", 0, month(2)]], coupon: 10_00}
        ])
      end
    end
  end

  context "with progressive billing" do
    let(:charges) do
      [{billable_metric_id: billable_metric.id, charge_model: "standard", pay_in_advance: false, properties: {amount: "1"}}]
    end
    let(:plan_options) { {usage_thresholds: [{amount_cents: 20_00, threshold_display_name: "Threshold"}]} }

    it "caps the coupon across the progressive billing and subscription invoices of each month" do
      ingest_on(Date.new(2025, 1, 10), 20)
      ingest_on(Date.new(2025, 1, 20), 10)
      bill_on(Date.new(2025, 2, 1))
      ingest_on(Date.new(2025, 2, 10), 20)
      ingest_on(Date.new(2025, 2, 20), 10)
      bill_on(Date.new(2025, 3, 1))

      expect(billed_invoices).to eq([])
    end
  end

  context "with a minimum commitment" do
    let(:plan_amount_cents) { 10_00 }
    let(:plan_options) { {minimum_commitment: {amount_cents: 50_00, invoice_display_name: "Minimum"}} }

    it "caps the coupon on each billed month" do
      bill_on(Date.new(2025, 2, 1))
      bill_on(Date.new(2025, 3, 1))

      expect(billed_invoices).to eq([])
    end
  end

  context "when the subscription is terminated during the month" do
    let(:plan_amount_cents) { 10_00 }
    let(:plan_pay_in_advance) { true }
    let(:charges) do
      [{billable_metric_id: billable_metric.id, charge_model: "standard", pay_in_advance: false, properties: {amount: "1"}}]
    end

    it "caps the termination invoice with the other invoices of its month" do
      ingest_on(Date.new(2025, 1, 10), 20)
      bill_on(Date.new(2025, 2, 1))
      ingest_on(Date.new(2025, 2, 10), 20)
      travel_to(Time.zone.parse("2025-02-15 12:00")) { terminate_subscription(subscription) }

      expect(billed_invoices).to eq([])
    end
  end

  context "with every fee type combined" do
    let(:coupon_amount_cents) { 40_00 }
    let(:plan_amount_cents) { 10_00 }
    let(:charges) do
      [
        {billable_metric_id: in_advance_billable_metric.id, charge_model: "standard", pay_in_advance: true, properties: {amount: "1"}},
        {billable_metric_id: billable_metric.id, charge_model: "standard", pay_in_advance: false, properties: {amount: "1"}}
      ]
    end
    let(:fixed_charges) do
      [
        {add_on_id: add_on.id, charge_model: "standard", units: 1, pay_in_advance: true, prorated: false, properties: {amount: "10"}},
        {add_on_id: in_arrears_add_on.id, charge_model: "standard", units: 1, pay_in_advance: false, prorated: false, properties: {amount: "5"}}
      ]
    end
    let(:plan_options) do
      {
        usage_thresholds: [{amount_cents: 20_00, threshold_display_name: "Threshold"}],
        minimum_commitment: {amount_cents: 100_00, invoice_display_name: "Minimum"}
      }
    end

    def bill_two_months
      ingest_on(Date.new(2025, 1, 10), 10, in_advance_billable_metric)
      ingest_on(Date.new(2025, 1, 20), 30)
      bill_on(Date.new(2025, 2, 1))
      ingest_on(Date.new(2025, 2, 10), 10, in_advance_billable_metric)
      ingest_on(Date.new(2025, 2, 20), 30)
      bill_on(Date.new(2025, 3, 1))
    end

    context "when the subscription is paid in arrears" do
      it "caps the coupon on the latest month billed by each invoice" do
        bill_two_months

        expect(billed_invoices).to eq([])
      end
    end

    context "when the subscription is paid in advance" do
      let(:plan_pay_in_advance) { true }

      it "caps the coupon on the latest month billed by each invoice" do
        bill_two_months

        expect(billed_invoices).to eq([])
      end
    end
  end
end
