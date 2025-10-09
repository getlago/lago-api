# frozen_string_literal: true

require "rails_helper"

describe "Subscription Downgrade Scenario", transaction: false do
  let(:organization) { create(:organization, webhook_url: false) }

  let(:customer) { create(:customer, organization:) }

  let(:monthly_plan) do
    create(
      :plan,
      organization:,
      interval: "monthly",
      amount_cents: 12_900,
      pay_in_advance: true
    )
  end

  let(:yearly_plan) do
    create(
      :plan,
      organization:,
      interval: "yearly",
      amount_cents: 118_800,
      pay_in_advance: true
    )
  end

  let(:subscription_at) { DateTime.new(2023, 7, 19, 12, 12) }

  it "downgrades and bill subscriptions" do
    subscription = nil

    # NOTE: Jul 19th: create the subscription
    travel_to(subscription_at) do
      create_subscription(
        {
          external_customer_id: customer.external_id,
          external_id: customer.external_id,
          plan_code: monthly_plan.code,
          billing_time: "anniversary",
          subscription_at: subscription_at.iso8601
        }
      )

      subscription = customer.subscriptions.first
      expect(subscription).to be_active
      expect(subscription.invoices.count).to eq(1)

      invoice = subscription.invoices.last
      expect(invoice.fees_amount_cents).to eq(monthly_plan.amount_cents)
      expect(invoice.invoice_subscriptions.first.from_datetime.iso8601).to eq("2023-07-19T00:00:00Z")
      expect(invoice.invoice_subscriptions.first.to_datetime.iso8601).to eq("2023-08-18T23:59:59Z")
    end

    # NOTE: August 19th: Bill subscription
    travel_to(DateTime.new(2023, 8, 19, 12, 12)) do
      expect { perform_billing }.to change { subscription.reload.invoices.count }

      expect(subscription.invoices.count).to eq(2)

      invoice = subscription.invoices.order(created_at: :asc).last
      expect(invoice.fees_amount_cents).to eq(monthly_plan.amount_cents)
      expect(invoice.invoice_subscriptions.first.from_datetime.iso8601).to eq("2023-08-19T00:00:00Z")
      expect(invoice.invoice_subscriptions.first.to_datetime.iso8601).to eq("2023-09-18T23:59:59Z")
      expect(invoice.invoice_subscriptions.first.charges_from_datetime.iso8601).to eq("2023-07-19T12:12:00Z")
      expect(invoice.invoice_subscriptions.first.charges_to_datetime.iso8601).to eq("2023-08-18T23:59:59Z")
    end

    # NOTE: September 19th: Bill subscription
    travel_to(DateTime.new(2023, 9, 19, 12, 12)) do
      expect { perform_billing }.to change { subscription.reload.invoices.count }

      expect(subscription.invoices.count).to eq(3)

      invoice = subscription.invoices.order(created_at: :asc).last
      expect(invoice.fees_amount_cents).to eq(monthly_plan.amount_cents)
      expect(invoice.invoice_subscriptions.first.from_datetime.iso8601).to eq("2023-09-19T00:00:00Z")
      expect(invoice.invoice_subscriptions.first.to_datetime.iso8601).to eq("2023-10-18T23:59:59Z")
      expect(invoice.invoice_subscriptions.first.charges_from_datetime.iso8601).to eq("2023-08-19T00:00:00Z")
      expect(invoice.invoice_subscriptions.first.charges_to_datetime.iso8601).to eq("2023-09-18T23:59:59Z")
    end

    # NOTE: October 19th: Bill subscription
    travel_to(DateTime.new(2023, 10, 19, 12, 12)) do
      expect { perform_billing }.to change { subscription.reload.invoices.count }

      expect(subscription.invoices.count).to eq(4)

      invoice = subscription.invoices.order(created_at: :asc).last
      expect(invoice.fees_amount_cents).to eq(monthly_plan.amount_cents)
      expect(invoice.invoice_subscriptions.first.from_datetime.iso8601).to eq("2023-10-19T00:00:00Z")
      expect(invoice.invoice_subscriptions.first.to_datetime.iso8601).to eq("2023-11-18T23:59:59Z")
      expect(invoice.invoice_subscriptions.first.charges_from_datetime.iso8601).to eq("2023-09-19T00:00:00Z")
      expect(invoice.invoice_subscriptions.first.charges_to_datetime.iso8601).to eq("2023-10-18T23:59:59Z")
    end

    # NOTE: On November 9th: Downgrade to the yearly plan
    travel_to(DateTime.new(2023, 11, 9, 0, 0)) do
      create_subscription(
        {
          external_customer_id: customer.external_id,
          external_id: customer.external_id,
          plan_code: yearly_plan.code,
          billing_time: "anniversary"
        }
      )

      expect(subscription.reload).to be_active
      expect(subscription.invoices.count).to eq(4)
    end

    # NOTE: November 19th: Bill subscription. Old subscription is terminated and pending one is activated
    travel_to(DateTime.new(2023, 11, 19, 12, 12)) do
      expect { perform_billing }.to change { subscription.reload.invoices.count }
      expect(subscription.reload).to be_terminated
      expect(subscription.invoices.count).to eq(5)
      expect(customer.invoices.count).to eq(5)

      new_subscription = subscription.reload.next_subscription

      expect(new_subscription.reload).to be_active
      expect(new_subscription.invoices.count).to eq(1)

      new_sub_invoice = new_subscription.invoices.order(created_at: :asc).last
      # There are 243 days from new sub started_at until old subscription subscription_at. Also, 2024 is a leap year
      # Also for old pay in advance plan there are no charges so total amount is zero
      expect(new_sub_invoice.fees_amount_cents).to eq(0 + (yearly_plan.amount_cents.fdiv(366) * 243).round)
      expect(new_subscription.invoice_subscriptions.order(created_at: :desc).first.from_datetime.iso8601)
        .to eq("2023-11-19T00:00:00Z")
      expect(new_subscription.invoice_subscriptions.order(created_at: :desc).first.to_datetime.iso8601)
        .to eq("2024-07-18T23:59:59Z")
    end
  end
end
