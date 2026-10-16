# frozen_string_literal: true

require "rails_helper"

describe "Upgrade terminated within the upgrade billing second" do
  let(:organization) { create(:organization, webhook_url: nil, email_settings: []) }
  let(:customer) { create(:customer, organization:, invoice_grace_period: 3) }
  let(:arrears_plan) { create(:plan, organization:, interval: "monthly", amount_cents: 1_000, pay_in_advance: false) }
  let(:advance_plan) { create(:plan, organization:, interval: "monthly", amount_cents: 5_000, pay_in_advance: true) }

  it "finalizes the upgrade invoice with its original invoicing reasons" do
    travel_to(DateTime.new(2026, 10, 2, 7, 24)) do
      create_subscription(
        {
          external_customer_id: customer.external_id,
          external_id: customer.external_id,
          plan_code: arrears_plan.code
        }
      )
    end

    previous_subscription = customer.subscriptions.sole

    travel_to(DateTime.new(2026, 10, 2, 7, 25, 31)) do
      create_subscription(
        {
          external_customer_id: customer.external_id,
          external_id: customer.external_id,
          plan_code: advance_plan.code
        }
      )
    end

    new_subscription = previous_subscription.reload.next_subscription
    upgrade_invoice = new_subscription.invoices.sole
    expected_invoicing_reasons = [
      [previous_subscription.id, "subscription_terminating"],
      [new_subscription.id, "subscription_starting"]
    ]

    expect(upgrade_invoice).to be_draft
    expect(upgrade_invoice.invoice_subscriptions.pluck(:subscription_id, :invoicing_reason))
      .to match_array(expected_invoicing_reasons)

    # The upgrade invoice is timestamped one second after the upgrade, so a termination in the upgrade second precedes it.
    travel_to(DateTime.new(2026, 10, 2, 7, 25, 31)) do
      terminate_subscription(new_subscription)
    end

    termination_invoice = new_subscription.invoices.where.not(id: upgrade_invoice.id).sole
    expect(new_subscription.reload).to be_terminated
    expect(termination_invoice).to be_draft

    travel_to(DateTime.new(2026, 10, 6, 1)) do
      perform_finalize_refresh
    end

    expect(upgrade_invoice.reload).to be_finalized
    expect(termination_invoice.reload).to be_finalized
    expect(upgrade_invoice.invoice_subscriptions.pluck(:subscription_id, :invoicing_reason))
      .to match_array(expected_invoicing_reasons)
  end
end
