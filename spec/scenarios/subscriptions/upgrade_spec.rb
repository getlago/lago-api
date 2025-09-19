# frozen_string_literal: true

require "rails_helper"

describe "Subscription Upgrade Scenario", transaction: false do
  let(:organization) { create(:organization, webhook_url: false, email_settings: []) }

  let(:customer) { create(:customer, organization:) }

  let(:monthly_plan) do
    create(
      :plan,
      organization:,
      interval: "monthly",
      amount_cents: 1000,
      pay_in_advance: true
    )
  end

  let(:yearly_plan) do
    create(
      :plan,
      organization:,
      interval: "yearly",
      amount_cents: 12_000,
      pay_in_advance: true
    )
  end

  let(:subscription_at) { DateTime.new(2023, 6, 29, 12, 12) }

  it "upgrades and bill subscriptions on a regular basis" do
    subscription = nil

    # NOTE: Jun 29th: create the subscription
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
      expect(invoice.invoice_subscriptions.first.from_datetime.iso8601).to eq("2023-06-29T00:00:00Z")
      expect(invoice.invoice_subscriptions.first.to_datetime.iso8601).to eq("2023-07-28T23:59:59Z")
    end

    # NOTE: July 29th: Bill subscription
    travel_to(DateTime.new(2023, 7, 29, 12, 12)) do
      expect { perform_billing }.to change { subscription.reload.invoices.count }

      expect(subscription.invoices.count).to eq(2)

      invoice = subscription.invoices.order(created_at: :asc).last
      expect(invoice.fees_amount_cents).to eq(monthly_plan.amount_cents)
      expect(invoice.invoice_subscriptions.first.from_datetime.iso8601).to eq("2023-07-29T00:00:00Z")
      expect(invoice.invoice_subscriptions.first.to_datetime.iso8601).to eq("2023-08-28T23:59:59Z")
      expect(invoice.invoice_subscriptions.first.charges_from_datetime.iso8601).to eq("2023-06-29T12:12:00Z")
      expect(invoice.invoice_subscriptions.first.charges_to_datetime.iso8601).to eq("2023-07-28T23:59:59Z")
    end

    # NOTE: August 29th: Bill subscription
    travel_to(DateTime.new(2023, 8, 29, 12, 12)) do
      expect { perform_billing }.to change { subscription.reload.invoices.count }

      expect(subscription.invoices.count).to eq(3)

      invoice = subscription.invoices.order(created_at: :asc).last
      expect(invoice.fees_amount_cents).to eq(monthly_plan.amount_cents)
      expect(invoice.invoice_subscriptions.first.from_datetime.iso8601).to eq("2023-08-29T00:00:00Z")
      expect(invoice.invoice_subscriptions.first.to_datetime.iso8601).to eq("2023-09-28T23:59:59Z")
      expect(invoice.invoice_subscriptions.first.charges_from_datetime.iso8601).to eq("2023-07-29T00:00:00Z")
      expect(invoice.invoice_subscriptions.first.charges_to_datetime.iso8601).to eq("2023-08-28T23:59:59Z")
    end

    # NOTE: On september 28th: Upgrade to the yearly plan
    travel_to(DateTime.new(2023, 9, 28, 5, 0)) do
      create_subscription(
        {
          external_customer_id: customer.external_id,
          external_id: customer.external_id,
          plan_code: yearly_plan.code,
          billing_time: "anniversary"
        }
      )

      expect(subscription.reload).to be_terminated
      expect(subscription.invoices.count).to eq(4)
      expect(customer.invoices.count).to eq(4)

      # expect(invoice.invoice_subscriptions.first.from_datetime.iso8601).to eq('2023-08-29T00:00:00Z')
      # expect(invoice.invoice_subscriptions.first.to_datetime.iso8601).to eq('2023-09-28T23:59:59Z')
      expect(subscription.invoice_subscriptions.order(created_at: :desc).first.charges_from_datetime.iso8601)
        .to eq("2023-08-29T00:00:00Z")
      expect(subscription.invoice_subscriptions.order(created_at: :desc).first.charges_to_datetime.iso8601)
        .to eq("2023-09-28T05:00:00Z")

      new_subscription = customer.subscriptions.order(created_at: :asc).last
      expect(new_subscription.plan.code).to eq(yearly_plan.code)
      expect(new_subscription).to be_active
      expect(new_subscription.invoices.count).to eq(1)

      invoice = new_subscription.invoices.last

      expect(customer.credit_notes.first.credit_amount_cents).to eq(32) # 1000 / 31

      number_of_days = (DateTime.new(2024, 6, 29, 0, 0) - DateTime.new(2023, 9, 28, 0, 0)).to_i
      single_day_price = 12_000.fdiv(366)

      expect(invoice.fees_amount_cents).to eq((number_of_days * single_day_price).round)
    end
  end
end
