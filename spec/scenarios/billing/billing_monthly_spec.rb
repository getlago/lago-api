# frozen_string_literal: true

require "rails_helper"
describe "Billing Monthly Scenarios with all charges types" do

  let(:organization) { create(:organization, webhook_url: nil) }
  let(:timezone) { "UTC" }
  let(:customer) { create(:customer, organization:, timezone:) }
  let(:plan) do
    create(
      :plan,
      organization:,
      amount_cents: 5_000_000,
      interval: "monthly",
      pay_in_advance: false
    )
  end
  let(:billable_metric_metered) do
    create(
      :billable_metric,
      organization:,
      name: "Metered in arrears",
      code: "metered",
      aggregation_type: "sum_agg",
      field_name: "total",
      recurring: false
    )
  end
  let(:billable_metric_recurring) do
    create(
      :billable_metric,
      organization:,
      name: "Recurring",
      code: "recurring",
      aggregation_type: "sum_agg",
      field_name: "total",
      recurring: true
    )
  end
  let(:charge_metered_prorated_in_arrears) do
    create(
      :package_charge,
      plan:,
      billable_metric: billable_metric_metered,
      properties: { amount: "100", package_size: 10, free_units: 0 },
      prorated: false,
      pay_in_advance: false
    )
  end
  let(:charge_metered_prorated_in_advance) do
    create(
      :package_charge,
      plan:,
      billable_metric: billable_metric_metered,
      properties: { amount: "1000", package_size: 10, free_units: 2 },
      prorated: false,
      pay_in_advance: true
    )
  end
  let(:charge_recurring_not_prorated_in_arrears) do
    create(
      :charge,
      plan:,
      billable_metric: billable_metric_recurring,
      properties: { amount: "5000" },
      prorated: true,
      pay_in_advance: false
    )
  end
  let(:charge_recurring_not_prorated_in_advance) do
    create(
      :charge,
      plan:,
      billable_metric: billable_metric_recurring,
      properties: { amount: "50000" },
      prorated: false,
      pay_in_advance: true
    )
  end
  let(:add_on) { create(:add_on)}
  let(:fixed_charge_not_prorated_in_arrears) { create(:fixed_charge, plan:, add_on:, units: 10, properties: { amount: "200" }, prorated: false, pay_in_advance: false) }
  let(:fixed_charge_not_prorated_in_advance) { create(:fixed_charge, plan:, add_on:, units: 10, properties: { amount: "200" }, prorated: false, pay_in_advance: true) }
  let(:fixed_charge_prorated_in_arrears) { create(:fixed_charge, plan:, add_on:, units: 10, properties: { amount: "200" }, prorated: true, pay_in_advance: false) }
  let(:fixed_charge_prorated_in_advance) { create(:fixed_charge, plan:, add_on:, units: 10, properties: { amount: "200" }, prorated: true, pay_in_advance: true) }

  before do
    charge_metered_prorated_in_arrears
    charge_metered_prorated_in_advance
    charge_recurring_not_prorated_in_arrears
    charge_recurring_not_prorated_in_advance
    fixed_charge_not_prorated_in_arrears
    fixed_charge_not_prorated_in_advance
    fixed_charge_prorated_in_arrears
    fixed_charge_prorated_in_advance
  end

  context "with calendar billing" do
    let(:billing_time) { "calendar" }
    # february leap year!
    let(:subscription_time) { DateTime.new(2024, 2, 4) }

    it "work the whole year" do
      subscription_date = DateTime.new(2024, 2, 4)
      travel_to subscription_date do
        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: customer.external_id,
            plan_code: plan.code,
            billing_time:
          }
        )
      end
      subscription = customer.subscriptions.first
      travel_to subscription_date + 10.minutes do
        perform_billing
      end
      # it immediately creates invoice with pay_in_advance fixed_charges
      expect(subscription.reload.invoices.count).to eq(1)
      pay_in_advance_fixed_charges_invoice = subscription.invoices.first
      byebug
      expect(pay_in_advance_fixed_charges_invoice.fees.fixed_charges.count).to eq(2)

      # 28th of Feb - before billing, no usage sent for usage charges
      time = DateTime.new(2024, 2, 28)
      travel_to(time) do
        perform_billing
      end
      subscription.reload.invoices
    end
  end
end