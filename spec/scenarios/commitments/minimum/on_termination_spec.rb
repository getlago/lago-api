# frozen_string_literal: true

require "rails_helper"

describe "Minimum Commitment On Termination Scenario", transaction: false do
  let(:organization) { create(:organization, webhook_url: nil) }
  let(:customer) { create(:customer, organization:, timezone: "UTC", currency: "EUR") }

  let(:plan) do
    create(
      :plan,
      organization:,
      name: "Enterprise",
      code: "enterprise",
      amount_cents: 10_000,
      amount_currency: "EUR",
      interval: "monthly",
      pay_in_advance: false
    )
  end

  let(:pricier_plan) do
    create(:plan, organization:, code: "pricier", amount_cents: 50_000, amount_currency: "EUR", interval: "monthly", pay_in_advance: false)
  end

  let(:cheaper_plan) do
    create(:plan, organization:, code: "cheaper", amount_cents: 1_000, amount_currency: "EUR", interval: "monthly", pay_in_advance: false)
  end

  let(:subscription) { customer.subscriptions.order(created_at: :asc).first.reload }
  let(:termination_invoice) { subscription.invoices.order(created_at: :asc).last }

  before do
    create(:commitment, :minimum_commitment, plan:, amount_cents: 1_000_000)

    # March 1st: subscribe to the monthly plan carrying the minimum commitment
    travel_to(DateTime.new(2024, 3, 1)) do
      create_subscription(
        {
          external_customer_id: customer.external_id,
          external_id: customer.external_id,
          plan_code: plan.code,
          billing_time: "calendar"
        }
      )
    end

    # April 1st and May 1st: the two periodic billing runs
    [DateTime.new(2024, 4, 1), DateTime.new(2024, 5, 1)].each do |billing_time|
      travel_to(billing_time) { perform_billing }
    end
  end

  it "bills March and April with a minimum commitment true-up fee" do
    expect(subscription.invoices.count).to eq(2)

    subscription.invoices.order(created_at: :asc).each do |invoice|
      expect(invoice.fees.commitment.count).to eq(1)
      expect(invoice.total_amount_cents).to eq(1_000_000)
    end
  end

  context "when the subscription is upgraded on June 1st at 10 AM" do
    before { pricier_plan }

    it "generates the termination invoice" do
      travel_to(DateTime.new(2024, 6, 1, 10)) do
        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: customer.external_id,
            plan_code: pricier_plan.code,
            billing_time: "calendar"
          }
        )
      end

      expect(subscription.reload).to be_terminated
      expect(termination_invoice).to be_finalized

      invoice_subscription = termination_invoice.invoice_subscriptions.sole
      expect(invoice_subscription.from_datetime.iso8601).to eq("2024-06-01T00:00:00Z")
      expect(invoice_subscription.to_datetime.iso8601).to eq("2024-06-01T10:00:00Z")
      expect(termination_invoice.fees.commitment.count).to eq(1)
    end
  end

  context "when the subscription is downgraded and the downgrade is applied on June 1st" do
    before { cheaper_plan }

    # The downgrade is requested mid-period and applied by the billing run on the
    # first day of the next period, a few minutes after midnight.
    it "generates the termination invoice" do
      travel_to(DateTime.new(2024, 5, 15)) do
        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: customer.external_id,
            plan_code: cheaper_plan.code,
            billing_time: "calendar"
          }
        )
      end

      expect(customer.subscriptions.reload.pluck(:status)).to match_array(%w[active pending])

      travel_to(DateTime.new(2024, 6, 1, 0, 15, 49)) { perform_billing }

      expect(subscription.reload).to be_terminated
      expect(termination_invoice).to be_finalized

      # The termination invoice covers the whole May period: on a downgrade the old
      # plan is billed up to the end of its last full period.
      invoice_subscription = termination_invoice.invoice_subscriptions.sole
      expect(invoice_subscription.from_datetime.iso8601).to eq("2024-05-01T00:00:00Z")
      expect(invoice_subscription.to_datetime.iso8601).to eq("2024-05-31T23:59:59Z")

      # A full period was consumed, so the whole commitment is due, exactly like the
      # March and April invoices above.
      expect(termination_invoice.fees.subscription.sole.amount_cents).to eq(10_000)
      expect(termination_invoice.fees.commitment.sole.amount_cents).to eq(990_000)
      expect(termination_invoice.total_amount_cents).to eq(1_000_000)
    end
  end
end
