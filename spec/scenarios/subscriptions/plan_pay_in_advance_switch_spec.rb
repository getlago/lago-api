# frozen_string_literal: true

require "rails_helper"

describe "Plan subscription fee switched from in arrears to in advance" do
  let(:organization) { create(:organization, webhook_url: nil) }
  let(:customer) { create(:customer, organization:, timezone: "UTC") }
  let(:plan) { organization.plans.find_by(code: "arrears_plan") }
  let(:metric) { organization.billable_metrics.find_by(code: "api_calls") }
  let(:subscription) { customer.subscriptions.sole }
  let(:start_date) { DateTime.new(2024, 3, 10) }
  let(:flip_date) { DateTime.new(2024, 4, 20) }
  let(:early_termination_date) { DateTime.new(2024, 4, 25, 12) }
  let(:late_termination_date) { DateTime.new(2024, 5, 25, 12) }

  def last_invoice
    subscription.reload.invoices.order(:created_at).last
  end

  def send_usage(units)
    create_event({code: metric.code, external_subscription_id: subscription.external_id, properties: {total: units}})
  end

  def billed_subscription_periods
    subscription.fees.subscription.order(:created_at).map { |f| f.properties.values_at("from_datetime", "to_datetime") }
  end

  def flip_to_pay_in_advance
    travel_to(DateTime.new(2024, 4, 15)) { send_usage(5) }
    travel_to(flip_date) { plan.reload.update!(pay_in_advance: true) }
    travel_to(DateTime.new(2024, 4, 22)) { send_usage(7) }
  end

  def bill_second_period
    travel_to(DateTime.new(2024, 5, 10, 1)) { perform_billing }
  end

  def expect_termination_invoice(charge_amount_cents:, charges_from:, charges_to:)
    invoice = last_invoice
    expect(invoice.fees.subscription.count).to eq(0)
    expect(invoice.fees_amount_cents).to eq(charge_amount_cents)
    expect(invoice.fees.charge.sole).to have_attributes(amount_cents: charge_amount_cents)
    expect(invoice.fees.charge.sole.properties).to include(
      "charges_from_datetime" => match_datetime(charges_from),
      "charges_to_datetime" => match_datetime(charges_to)
    )
  end

  def terminate_at(date, params = {})
    travel_to(date) { terminate_subscription(subscription, params:) }
    subscription.reload
  end

  before do
    travel_to(start_date) do
      create_metric({name: "API calls", code: "api_calls", aggregation_type: "sum_agg", field_name: "total"})
      create_plan(
        {
          name: "Arrears plan",
          code: "arrears_plan",
          interval: "monthly",
          amount_cents: 5_00,
          amount_currency: "EUR",
          pay_in_advance: false,
          trial_period: 31,
          charges: [{billable_metric_id: metric.id, charge_model: "standard", pay_in_advance: false, properties: {amount: "1"}}]
        }
      )
      create_subscription(
        {
          external_customer_id: customer.external_id,
          external_id: "sub_1",
          plan_code: plan.code,
          billing_time: "anniversary"
        }
      )
    end

    travel_to(DateTime.new(2024, 3, 20)) { send_usage(10) }
    travel_to(DateTime.new(2024, 4, 10, 1)) { perform_billing }
  end

  it "leaves a period without subscription fee" do
    invoice = last_invoice
    expect(subscription.invoices.count).to eq(1)
    expect(invoice.fees.subscription.sole).to have_attributes(amount_cents: 0)
    expect(invoice.fees.subscription.sole.properties).to include(
      "from_datetime" => match_datetime("2024-03-10T00:00:00Z"),
      "to_datetime" => match_datetime("2024-04-09T23:59:59Z")
    )
    expect(invoice.fees.charge.sole).to have_attributes(amount_cents: 10_00)
    expect(invoice.fees.charge.sole.properties).to include(
      "charges_from_datetime" => match_datetime("2024-03-10T00:00:00Z"),
      "charges_to_datetime" => match_datetime("2024-04-09T23:59:59Z")
    )
    expect(invoice.total_amount_cents).to eq(10_00)

    flip_to_pay_in_advance
    bill_second_period

    invoice = last_invoice
    expect(subscription.invoices.count).to eq(2)
    expect(invoice.invoice_subscriptions.sole).to have_attributes(
      from_datetime: match_datetime("2024-05-10T00:00:00Z"),
      to_datetime: match_datetime("2024-06-09T23:59:59Z"),
      charges_from_datetime: match_datetime("2024-04-10T00:00:00Z"),
      charges_to_datetime: match_datetime("2024-05-09T23:59:59Z")
    )
    expect(invoice.fees.subscription.sole).to have_attributes(amount_cents: 5_00)
    expect(invoice.fees.subscription.sole.properties).to include(
      "from_datetime" => match_datetime("2024-05-10T00:00:00Z"),
      "to_datetime" => match_datetime("2024-06-09T23:59:59Z")
    )
    expect(invoice.fees.charge.sole).to have_attributes(amount_cents: 12_00)
    expect(invoice.fees.charge.sole.properties).to include(
      "charges_from_datetime" => match_datetime("2024-04-10T00:00:00Z"),
      "charges_to_datetime" => match_datetime("2024-05-09T23:59:59Z")
    )
    expect(invoice.total_amount_cents).to eq(17_00)

    expect(billed_subscription_periods).to eq([
      ["2024-03-10T00:00:00.000Z", "2024-04-09T23:59:59.999Z"],
      ["2024-05-10T00:00:00.000Z", "2024-06-09T23:59:59.999Z"]
    ])

    travel_to(DateTime.new(2024, 5, 15)) { send_usage(3) }
    terminate_at(late_termination_date)

    expect(subscription).to be_terminated
    expect(subscription.invoices.count).to eq(3)
    expect_termination_invoice(charge_amount_cents: 3_00, charges_from: "2024-05-10T00:00:00Z", charges_to: "2024-05-25T12:00:00Z")
  end

  # NOTE: Here everything happens as expected, like the subscription was always in-advance. Nothing to see.
  context "when terminated after the first in advance billing" do
    let(:advance_invoice) { subscription.invoices.order(:created_at).second }
    # 15 unused days (May 26 - June 9) out of 31
    let(:unused_amount_cents) { (5_00 * 15 / 31.0).round }

    before do
      flip_to_pay_in_advance
      bill_second_period
      travel_to(DateTime.new(2024, 5, 15)) { send_usage(3) }
    end

    after do
      expect_termination_invoice(charge_amount_cents: 3_00, charges_from: "2024-05-10T00:00:00Z", charges_to: "2024-05-25T12:00:00Z")
    end

    it "credits the unused days with on_termination_credit_note=credit" do
      terminate_at(late_termination_date, on_termination_credit_note: "credit")

      expect(subscription.on_termination_credit_note).to eq("credit")
      expect(advance_invoice.credit_notes.sole).to have_attributes(
        credit_amount_cents: unused_amount_cents,
        refund_amount_cents: 0,
        offset_amount_cents: 0
      )
    end

    it "creates no credit note with on_termination_credit_note=skip" do
      terminate_at(late_termination_date, on_termination_credit_note: "skip")

      expect(subscription.on_termination_credit_note).to eq("skip")
      expect(customer.credit_notes.count).to eq(0)
    end

    it "refunds the unused days with on_termination_credit_note=refund", :premium do
      create_payment(customer, advance_invoice, 17_00)

      terminate_at(late_termination_date, on_termination_credit_note: "refund")

      expect(subscription.on_termination_credit_note).to eq("refund")
      expect(advance_invoice.credit_notes.sole).to have_attributes(
        credit_amount_cents: 0,
        refund_amount_cents: unused_amount_cents,
        offset_amount_cents: 0
      )
    end

    it "offsets the unused days with on_termination_credit_note=offset" do
      terminate_at(late_termination_date, on_termination_credit_note: "offset")

      expect(subscription.on_termination_credit_note).to eq("offset")
      expect(advance_invoice.credit_notes.sole).to have_attributes(
        credit_amount_cents: 0,
        refund_amount_cents: 0,
        offset_amount_cents: unused_amount_cents
      )
    end
  end

  context "when terminated before the first in advance billing" do
    before { flip_to_pay_in_advance }

    after do
      expect_termination_invoice(charge_amount_cents: 12_00, charges_from: "2024-04-10T00:00:00Z", charges_to: "2024-04-25T12:00:00Z")
    end

    it "does not bill the partial period" do
      terminate_at(early_termination_date)

      expect(subscription).to be_terminated
      expect(subscription.invoices.count).to eq(2)

      expect(last_invoice.total_amount_cents).to eq(12_00)
      expect(billed_subscription_periods).to eq([["2024-03-10T00:00:00.000Z", "2024-04-09T23:59:59.999Z"]])
    end

    %w[credit skip refund offset].each do |on_termination_credit_note|
      it "creates no credit note with on_termination_credit_note=#{on_termination_credit_note}", :premium do
        create_payment(customer, last_invoice, 10_00)

        terminate_at(early_termination_date, on_termination_credit_note:)

        expect(subscription.on_termination_credit_note).to eq(on_termination_credit_note)
        expect(customer.credit_notes.count).to eq(0)
      end
    end
  end
end
