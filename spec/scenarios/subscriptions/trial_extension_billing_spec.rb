# frozen_string_literal: true

require "rails_helper"

# Regression scenario for https://github.com/getlago/lago/issues/771
describe "Trial Extension Billing Scenario", :scenarios, type: :request do
  let(:organization) { create(:organization, webhook_url: nil) }
  let(:customer) { create(:customer, organization:, timezone: "Europe/Ljubljana") }
  let(:plan) do
    create(:plan, organization:, code: "pro", name: "Pro", interval: :monthly,
      amount_cents: 14_900, pay_in_advance: true, trial_period: 30)
  end

  around { |test| lago_premium!(&test) }

  it "bills an extended trial on the trial end date in the customer timezone" do
    # Signup late in the local day (23:47) on an overridden plan, 30 day trial
    travel_to(Time.zone.parse("2026-06-15 21:47:00 UTC")) do
      create_subscription(
        {external_customer_id: customer.external_id, external_id: customer.external_id,
         plan_code: plan.code, plan_overrides: {name: "Pro (custom)"}}
      )
      expect(customer.reload.invoices.count).to eq(0)
    end

    # Calendar billing day: $0 advance invoice, the whole period is inside the trial
    travel_to(Time.zone.parse("2026-07-01 00:35:00 UTC")) { perform_billing }
    expect(customer.reload.invoices.count).to eq(1)
    expect(customer.invoices.sole.total_amount_cents).to eq(0)

    # Trial extended from 30 to 41 days by re-assigning the plan with different overrides.
    # Lago models this as a plan change: terminate the current subscription, create a new one.
    travel_to(Time.zone.parse("2026-07-15 10:00:00 UTC")) do
      create_subscription(
        {external_customer_id: customer.external_id, external_id: customer.external_id,
         plan_code: plan.code, plan_overrides: {name: "Pro (custom)", trial_period: 41}}
      )
    end

    expect(customer.subscriptions.terminated.count).to eq(1)
    active = customer.subscriptions.active.sole
    expect(active.started_at.to_date.iso8601).to eq("2026-07-15")
    expect(active.subscription_at.to_date.iso8601).to eq("2026-06-15") # customer-facing date preserved
    expect(active.plan.trial_period).to eq(41)
    expect(customer.invoices.order(:created_at).last.total_amount_cents).to eq(0) # termination invoice

    # Last tick of Jul 25 local: trial end date not reached, nothing bills
    travel_to(Time.zone.parse("2026-07-25 21:35:00 UTC")) { perform_billing } # Jul 25 23:35 local
    expect(customer.reload.invoices.count).to eq(2)

    # First tick of Jul 26 local: 41 day trial (anchored to the original Jun 15 start) is over.
    # The invoice is issued ON the trial end date even though the signup time of day (23:47)
    # has not passed yet; the fee below already charges the whole of Jul 26.
    travel_to(Time.zone.parse("2026-07-25 22:35:00 UTC")) { perform_billing } # Jul 26 00:35 local
    expect(customer.reload.invoices.count).to eq(3)
    invoice = customer.invoices.order(created_at: :desc).first
    expect(invoice.issuing_date.iso8601).to eq("2026-07-26")
    expect(invoice.fees.subscription.first.amount_cents).to eq(2_884) # 6 days (Jul 26..31) at $149/31

    # Later ticks do not bill again
    travel_to(Time.zone.parse("2026-07-26 22:35:00 UTC")) { perform_billing } # Jul 27 00:35 local
    expect(customer.reload.invoices.count).to eq(3)
  end
end
