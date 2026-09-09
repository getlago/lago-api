# frozen_string_literal: true

require "rails_helper"

describe "Subscription Proration On Termination Scenario" do
  let(:organization) { create(:organization, webhook_url: nil) }
  let(:customer) { create(:customer, organization:, timezone: "UTC") }

  # NOTE: the amount is a multiple of the quarter duration, so that a single day costs 1000 cents
  #       when the proration is based on the whole period.
  let(:plan) do
    create(:plan, organization:, interval: :quarterly, pay_in_advance: false, amount_cents: 91_000)
  end

  let(:cheaper_plan) do
    create(:plan, organization:, interval: :quarterly, pay_in_advance: false, amount_cents: 45_500)
  end

  context "when the subscription results from an upgrade" do
    it "prorates the terminated fee on the whole period" do
      subscription = nil

      travel_to(Time.zone.parse("2024-01-15T10:00:00Z")) do
        create_subscription(
          {external_customer_id: customer.external_id,
           external_id: customer.external_id,
           plan_code: cheaper_plan.code,
           billing_time: "anniversary"}
        )
      end

      # NOTE: the upgrade terminates the first subscription and starts the new one in the middle of
      #       the period opened on 15 Apr, whose anniversary the new subscription inherits.
      travel_to(Time.zone.parse("2024-05-20T10:00:00Z")) do
        create_subscription(
          {external_customer_id: customer.external_id,
           external_id: customer.external_id,
           plan_code: plan.code,
           billing_time: "anniversary"}
        )

        subscription = customer.subscriptions.order(:created_at).last
        expect(subscription.plan).to eq(plan)
        expect(subscription.subscription_at.iso8601).to eq("2024-01-15T10:00:00Z")
        expect(subscription.started_at.iso8601).to eq("2024-05-20T10:00:00Z")
      end

      travel_to(Time.zone.parse("2024-06-20T10:00:00Z")) do
        terminate_subscription(subscription)

        invoice = subscription.reload.invoices.order(:created_at).last
        fee = invoice.fees.subscription.sole

        expect(fee.amount_cents).to eq(32_000)
      end
    end
  end

  context "when the subscription started in the middle of a calendar period" do
    it "prorates the terminated fee on the whole period" do
      subscription = nil

      travel_to(Time.zone.parse("2024-05-20T10:00:00Z")) do
        create_subscription(
          {external_customer_id: customer.external_id,
           external_id: customer.external_id,
           plan_code: plan.code,
           billing_time: "calendar"}
        )

        subscription = customer.subscriptions.sole
        expect(subscription.started_at.iso8601).to eq("2024-05-20T10:00:00Z")
      end

      travel_to(Time.zone.parse("2024-06-20T10:00:00Z")) do
        terminate_subscription(subscription)

        invoice = subscription.reload.invoices.order(:created_at).last
        fee = invoice.fees.subscription.sole

        expect(fee.amount_cents).to eq(32_000)
      end
    end
  end
end
