# frozen_string_literal: true

require "rails_helper"

describe "Refreshing a draft invoice keeps its pay in advance fixed charge", :premium do
  let(:organization) { create(:organization, webhook_url: nil) }
  let(:customer) { create(:customer, organization:, invoice_grace_period: 3, timezone: "UTC") }
  let(:add_on) { create(:add_on, organization:) }
  let(:plan) { create(:plan, organization:, amount_cents: 0, interval: "monthly", pay_in_advance: true) }

  # The plan carries no units; the subscription brings them as an override.
  let(:fixed_charge) do
    create(
      :fixed_charge,
      plan:,
      add_on:,
      units: 0,
      properties: {amount: "239.9"},
      prorated: true,
      pay_in_advance: true
    )
  end

  let(:subscription_date) { DateTime.new(2024, 3, 1) }
  let(:subscription) { customer.subscriptions.sole }
  let(:draft) { subscription.invoices.draft.sole }
  # 2 units x 239.90, a full calendar month so proration is a no-op
  let(:fee_amount_cents) { 47_980 }

  before do
    fixed_charge

    travel_to subscription_date do
      create_subscription(
        {
          external_customer_id: customer.external_id,
          external_id: "sub_#{customer.external_id}",
          plan_code: plan.code,
          billing_time: "calendar",
          plan_overrides: {fixed_charges: [{id: fixed_charge.id, units: 2}]}
        }
      )
    end

    # Repeating units that are already billed leaves the pay in advance run with nothing
    # to bill, so it writes a fee of zero units on a second invoice.
    travel_to subscription_date + 1.hour do
      update_subscription(
        subscription,
        {plan_overrides: {fixed_charges: [{id: fixed_charge.id, units: 2, apply_units_immediately: true}]}}
      )
    end
  end

  # Pins the setup itself: without this fee on a second invoice there is nothing for the
  # guard to misread, and the example below would pass whether or not the bug exists.
  it "leaves a fee that billed nothing on a second invoice" do
    placeholder = subscription.invoices.where.not(id: draft.id).sole

    expect(placeholder.fees.fixed_charge.sole).to have_attributes(units: 0, amount_cents: 0)
  end

  # A refresh destroys the fees and builds them again. The zero-unit fee on the other
  # invoice billed nothing, so it is not proof of billing and must not stop the rebuild.
  it "keeps the fee and the invoice total when the draft is refreshed" do
    expect(draft.fees.fixed_charge.sole.amount_cents).to eq(fee_amount_cents)

    travel_to subscription_date + 1.day do
      refresh_invoice(draft)
    end

    draft.reload
    expect(draft.fees.fixed_charge.sum(:amount_cents)).to eq(fee_amount_cents)
    expect(draft.total_amount_cents).to eq(fee_amount_cents)
  end
end
