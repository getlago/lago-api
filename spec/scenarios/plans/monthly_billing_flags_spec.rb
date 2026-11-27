# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Plan update keeps the monthly billing flags" do
  let(:organization) { create(:organization, webhook_url: nil) }
  let(:customer) { create(:customer, organization:) }
  let(:billable_metric) { create(:billable_metric, organization:, aggregation_type: "count_agg") }

  it "bills the charges of a yearly plan monthly after an update with only the name" do
    travel_to(Time.zone.parse("2025-12-15T10:00:00")) do
      create_plan(
        {
          name: "Yearly plan",
          code: "yearly_plan",
          interval: "yearly",
          amount_cents: 120_000,
          amount_currency: "EUR",
          pay_in_advance: false,
          bill_charges_monthly: true,
          charges: [
            {
              billable_metric_id: billable_metric.id,
              charge_model: "standard",
              properties: {amount: "10"}
            }
          ]
        }
      )
    end

    plan = organization.plans.find_by(code: "yearly_plan")

    travel_to(Time.zone.parse("2025-12-15T11:00:00")) do
      update_plan(plan, {name: "Renamed plan"})
    end

    expect(plan.reload).to have_attributes(name: "Renamed plan", bill_charges_monthly: true)

    travel_to(Time.zone.parse("2026-01-01T10:00:00")) do
      create_subscription(
        {
          external_customer_id: customer.external_id,
          external_id: "sub_yearly",
          plan_code: plan.code,
          billing_time: "calendar"
        }
      )
    end

    subscription = customer.subscriptions.find_by(external_id: "sub_yearly")

    travel_to(Time.zone.parse("2026-01-10T10:00:00")) do
      5.times do
        create_event(
          {
            code: billable_metric.code,
            external_subscription_id: subscription.external_id
          }
        )
      end
    end

    travel_to(Time.zone.parse("2026-02-01T10:00:00")) do
      perform_billing
    end

    expect(subscription.reload.invoices.count).to eq(1)

    invoice = subscription.invoices.first
    # Calendar yearly plan in arrears: the subscription fee is billed only in January, so February has none.
    expect(invoice.fees.subscription).to be_empty
    expect(invoice.fees.charge.pluck(:amount_cents)).to eq([5_000]) # 5 events x 10.00 EUR = 50.00 EUR
    expect(invoice.total_amount_cents).to eq(5_000) # one charge fee, no subscription fee, no taxes
  end
end
