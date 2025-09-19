# frozen_string_literal: true

require "rails_helper"

describe "Billing Boundaries Scenario" do
  let(:organization) { create(:organization, webhook_url: nil) }

  let(:timezone) { "UTC" }
  let(:customer) { create(:customer, organization:, timezone:) }

  let(:plan_interval) { :monthly }
  let(:plan_monthly_charges) { false }
  let(:plan_in_advance) { false }

  let(:billing_time) { "anniversary" }

  let(:plan) do
    create(
      :plan,
      organization:,
      interval: plan_interval,
      pay_in_advance: plan_in_advance,
      bill_charges_monthly: plan_monthly_charges
    )
  end

  it "creates invoices" do
    travel_to(Time.zone.parse("2024-01-31T01:00:00Z")) do
      create_subscription(
        {external_customer_id: customer.external_id,
         external_id: customer.external_id,
         plan_code: plan.code,
         billing_time:}
      )
    end

    subscription = customer.subscriptions.first

    # February billing
    travel_to(Time.zone.parse("2024-02-29T02:00:00Z")) do
      expect { perform_billing }.to change { subscription.reload.invoices.count }.by(1)
    end

    invoice = subscription.invoices.order(created_at: :desc).first
    invoice_subscription = invoice.invoice_subscriptions.first

    expect(invoice_subscription.from_datetime).to match_datetime("2024-01-31T00:00:00Z")
    expect(invoice_subscription.to_datetime).to match_datetime("2024-02-28T23:59:59Z")
    expect(invoice_subscription.charges_from_datetime).to match_datetime("2024-01-31T01:00:00Z")
    expect(invoice_subscription.charges_to_datetime).to match_datetime("2024-02-28T23:59:59Z")

    # March billing
    travel_to(Time.zone.parse("2024-03-31T02:00:00Z")) do
      expect { perform_billing }.to change { subscription.reload.invoices.count }.by(1)
    end

    invoice = subscription.invoices.order(created_at: :desc).first
    invoice_subscription = invoice.invoice_subscriptions.first

    expect(invoice_subscription.from_datetime).to match_datetime("2024-02-29T00:00:00Z")
    expect(invoice_subscription.to_datetime).to match_datetime("2024-03-30T23:59:59Z")
    expect(invoice_subscription.charges_from_datetime).to match_datetime("2024-02-29T00:00:00Z")
    expect(invoice_subscription.charges_to_datetime).to match_datetime("2024-03-30T23:59:59Z")

    # April billing
    travel_to(Time.zone.parse("2024-04-30T02:00:00Z")) do
      expect { perform_billing }.to change { subscription.reload.invoices.count }.by(1)
    end

    invoice = subscription.invoices.order(created_at: :desc).first
    invoice_subscription = invoice.invoice_subscriptions.first

    expect(invoice_subscription.from_datetime).to match_datetime("2024-03-31T00:00:00Z")
    expect(invoice_subscription.to_datetime).to match_datetime("2024-04-29T23:59:59Z")
    expect(invoice_subscription.charges_from_datetime).to match_datetime("2024-03-31T00:00:00Z")
    expect(invoice_subscription.charges_to_datetime).to match_datetime("2024-04-29T23:59:59Z")
  end

  context "with plans in advance" do
    let(:plan_in_advance) { true }

    it "creates invoices" do
      travel_to(Time.zone.parse("2024-01-30T00:00:00Z")) do
        create_subscription(
          {external_customer_id: customer.external_id,
           external_id: customer.external_id,
           plan_code: plan.code,
           billing_time:}
        )
      end

      subscription = customer.subscriptions.first
      expect(subscription.invoices.count).to eq(1)

      invoice = subscription.invoices.order(created_at: :desc).first
      invoice_subscription = invoice.invoice_subscriptions.first

      expect(invoice_subscription.from_datetime).to match_datetime("2024-01-30T00:00:00Z")
      expect(invoice_subscription.to_datetime).to match_datetime("2024-02-28T23:59:59Z")

      # February billing
      travel_to(Time.zone.parse("2024-02-29T02:00:00Z")) do
        expect { perform_billing }.to change { subscription.reload.invoices.count }.by(1)
      end

      invoice = subscription.invoices.order(created_at: :desc).first
      invoice_subscription = invoice.invoice_subscriptions.first

      expect(invoice_subscription.from_datetime).to match_datetime("2024-02-29T00:00:00Z")
      expect(invoice_subscription.to_datetime).to match_datetime("2024-03-29T23:59:59Z")
      expect(invoice_subscription.charges_from_datetime).to match_datetime("2024-01-30T00:00:00Z")
      expect(invoice_subscription.charges_to_datetime).to match_datetime("2024-02-28T23:59:59Z")

      # March billing
      travel_to(Time.zone.parse("2024-03-30T02:00:00Z")) do
        expect { perform_billing }.to change { subscription.reload.invoices.count }.by(1)
      end

      invoice = subscription.invoices.order(created_at: :desc).first
      invoice_subscription = invoice.invoice_subscriptions.first

      expect(invoice_subscription.from_datetime).to match_datetime("2024-03-30T00:00:00Z")
      expect(invoice_subscription.to_datetime).to match_datetime("2024-04-29T23:59:59Z")
      expect(invoice_subscription.charges_from_datetime).to match_datetime("2024-02-29T00:00:00Z")
      expect(invoice_subscription.charges_to_datetime).to match_datetime("2024-03-29T23:59:59Z")

      # April billing
      travel_to(Time.zone.parse("2024-04-30T02:00:00Z")) do
        expect { perform_billing }.to change { subscription.reload.invoices.count }.by(1)
      end

      invoice = subscription.invoices.order(created_at: :desc).first
      invoice_subscription = invoice.invoice_subscriptions.first

      expect(invoice_subscription.from_datetime).to match_datetime("2024-04-30T00:00:00Z")
      expect(invoice_subscription.to_datetime).to match_datetime("2024-05-29T23:59:59Z")
      expect(invoice_subscription.charges_from_datetime).to match_datetime("2024-03-30T00:00:00Z")
      expect(invoice_subscription.charges_to_datetime).to match_datetime("2024-04-29T23:59:59Z")
    end
  end
end
