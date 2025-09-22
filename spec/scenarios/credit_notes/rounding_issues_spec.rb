# frozen_string_literal: true

require "rails_helper"

describe "Credit note rounding issues Scenarios", :scenarios, type: :request do
  let(:organization) { create(:organization, webhook_url: nil, email_settings: []) }
  let(:customer) { create(:customer, organization:) }

  let(:tax) { create(:tax, :applied_to_billing_entity, organization:, rate: 25) }

  let(:plan) do
    create(:plan, organization:, interval: :monthly, amount_cents: 20000, pay_in_advance: true)
  end

  around { |test| lago_premium!(&test) }

  before do
    tax
    plan
  end

  it "handles the rounding issues" do
    # Creates the subscription
    travel_to(Time.zone.parse("2025-09-18T16:00:00Z")) do
      create_subscription({
        external_customer_id: customer.external_id,
        external_id: customer.external_id,
        plan_code: plan.code,
        billing_time: :anniversary
      })
    end

    subscription = customer.subscriptions.last
    invoice = customer.invoices.last
    expect(invoice.fees_amount_cents).to eq(20000)
    expect(invoice.taxes_amount_cents).to eq(5000)
    expect(invoice.total_amount_cents).to eq(25000)

    # Finalize the invoice
    travel_to(Time.zone.parse("2025-09-18T16:30:00Z")) do
      update_invoice(invoice, {payment_status: "succeeded"})
    end

    # Terminate subscription
    travel_to(Time.zone.parse("2025-09-18T16:40:00Z")) do
      terminate_subscription(subscription)
    end

    # Fetch the credit note
    credit_note = customer.credit_notes.last
    expect(credit_note).to have_attributes(
      sub_total_excluding_taxes_amount_cents: 19333,
      taxes_amount_cents: 4833,
      credit_amount_cents: 24166,
      total_amount_cents: 24166
    )
  end
end
