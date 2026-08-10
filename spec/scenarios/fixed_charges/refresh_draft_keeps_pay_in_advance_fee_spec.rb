# frozen_string_literal: true

require "rails_helper"

describe "Refreshing a draft invoice keeps its pay in advance fixed charge", :premium do
  let(:organization) { create(:organization, webhook_url: nil) }
  let(:customer) { create(:customer, organization:, invoice_grace_period: 3, timezone: "UTC") }
  let(:add_on) { create(:add_on, organization:) }
  let(:plan) { create(:plan, organization:, amount_cents: 0, interval: "monthly", pay_in_advance: true) }

  let(:fixed_charge) do
    create(
      :fixed_charge,
      plan:,
      add_on:,
      units: 2,
      properties: {amount: "239.9"},
      prorated: true,
      pay_in_advance: true
    )
  end

  let(:subscription_date) { DateTime.new(2024, 3, 1) }
  let(:subscription) { customer.subscriptions.sole }
  # The grace period keeps this one as a draft, so it is the invoice the refresh rebuilds.
  let(:draft) { subscription.invoices.order(:created_at).first }

  before do
    fixed_charge

    travel_to subscription_date do
      create_subscription(
        {
          external_customer_id: customer.external_id,
          external_id: "sub_#{customer.external_id}",
          plan_code: plan.code,
          billing_time: "calendar"
        }
      )
    end

    # Repeating units that are already billed leaves the pay in advance run with nothing
    # to bill, so it writes a fee of zero units on a second invoice.
    travel_to subscription_date + 1.second do
      update_subscription(
        subscription,
        {plan_overrides: {fixed_charges: [{id: fixed_charge.id, units: 2, apply_units_immediately: true}]}}
      )
      perform_all_enqueued_jobs
    end
  end

  # A refresh destroys the fees and builds them again. The zero-unit fee on the other
  # invoice billed nothing, so it is not proof of billing and must not stop the rebuild.
  it "keeps the fee and the invoice total when the draft is refreshed" do
    # 2 units x 239.90, a full calendar month so proration is a no-op
    expect(draft.fees.fixed_charge.sum(:amount_cents)).to eq(47_980)

    travel_to subscription_date + 1.day do
      refresh_invoice(draft)
    end

    draft.reload
    expect(draft.fees.fixed_charge.sum(:amount_cents)).to eq(47_980)
    expect(draft.total_amount_cents).to eq(47_980)
  end
end
