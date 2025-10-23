# frozen_string_literal: true

require "rails_helper"

describe "Billing Boundaries Scenario" do
  let(:organization) { create(:organization, webhook_url: nil) }

  let(:timezone) { "UTC" }
  let(:customer) { create(:customer, organization:, timezone:) }

  let(:plan_interval) { :monthly }
  let(:plan_monthly_charges) { false }
  let(:plan_monthly_fixed_charges) { false }
  let(:plan_in_advance) { false }
  let(:billable_metric) { create(:billable_metric, organization:) }
  let(:charge) { create(:standard_charge, plan:, billable_metric:) }
  let(:add_on) { create(:add_on, organization:) }
  let(:fixed_charge) { create(:fixed_charge, plan:, add_on:) }

  let(:billing_time) { "anniversary" }

  let(:plan) do
    create(
      :plan,
      organization:,
      interval: plan_interval,
      pay_in_advance: plan_in_advance,
      bill_charges_monthly: plan_monthly_charges,
      bill_fixed_charges_monthly: plan_monthly_fixed_charges
    )
  end

  before do
    charge
    fixed_charge
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
    expect(invoice_subscription.fixed_charges_from_datetime).to match_datetime("2024-01-31T01:00:00Z")
    expect(invoice_subscription.fixed_charges_to_datetime).to match_datetime("2024-02-28T23:59:59Z")

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
    expect(invoice_subscription.fixed_charges_from_datetime).to match_datetime("2024-02-29T00:00:00Z")
    expect(invoice_subscription.fixed_charges_to_datetime).to match_datetime("2024-03-30T23:59:59Z")

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
    expect(invoice_subscription.fixed_charges_from_datetime).to match_datetime("2024-03-31T00:00:00Z")
    expect(invoice_subscription.fixed_charges_to_datetime).to match_datetime("2024-04-29T23:59:59Z")
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
      expect(invoice_subscription.fixed_charges_from_datetime).to match_datetime("2024-01-30T00:00:00Z")
      expect(invoice_subscription.fixed_charges_to_datetime).to match_datetime("2024-02-28T23:59:59Z")

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
      expect(invoice_subscription.fixed_charges_from_datetime).to match_datetime("2024-02-29T00:00:00Z")
      expect(invoice_subscription.fixed_charges_to_datetime).to match_datetime("2024-03-29T23:59:59Z")
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
      expect(invoice_subscription.fixed_charges_from_datetime).to match_datetime("2024-03-30T00:00:00Z")
      expect(invoice_subscription.fixed_charges_to_datetime).to match_datetime("2024-04-29T23:59:59Z")
    end
  end

  context "when interval is yearly" do
    let(:plan_interval) { :yearly }

    it "creates invoices once a year" do
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
        expect { perform_billing }.not_to change { subscription.reload.invoices.count }
      end

      # March billing
      travel_to(Time.zone.parse("2024-03-31T02:00:00Z")) do
        expect { perform_billing }.not_to change { subscription.reload.invoices.count }
      end

      # April billing
      travel_to(Time.zone.parse("2024-04-30T02:00:00Z")) do
        expect { perform_billing }.not_to change { subscription.reload.invoices.count }
      end

      # next year billing
      travel_to(Time.zone.parse("2025-01-31T02:00:00Z")) do
        expect { perform_billing }.to change { subscription.reload.invoices.count }.by(1)
      end

      invoice = subscription.invoices.order(created_at: :desc).first
      invoice_subscription = invoice.invoice_subscriptions.first

      expect(invoice_subscription.from_datetime).to match_datetime("2024-01-31T00:00:00Z")
      expect(invoice_subscription.to_datetime).to match_datetime("2025-01-30T23:59:59Z")
      expect(invoice_subscription.charges_from_datetime).to match_datetime("2024-01-31T01:00:00Z")
      expect(invoice_subscription.charges_to_datetime).to match_datetime("2025-01-30T23:59:59Z")
      expect(invoice_subscription.fixed_charges_from_datetime).to match_datetime("2024-01-31T01:00:00Z")
      expect(invoice_subscription.fixed_charges_to_datetime).to match_datetime("2025-01-30T23:59:59Z")
    end

    context "when charges are billed monthly" do
      let(:plan_monthly_charges) { true }

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

        travel_to(Time.zone.parse("2024-02-01T00:00:00Z")) do
          create_event(
            {
              transaction_id: SecureRandom.uuid,
              external_subscription_id: subscription.external_id,
              code: billable_metric.code,
              properties: {
                billable_metric.field_name => 10
              }
            }
          )
        end

        # February billing
        travel_to(Time.zone.parse("2024-02-29T02:00:00Z")) do
          expect { perform_billing }.to change { subscription.reload.invoices.count }.by(1)
        end

        invoice = subscription.invoices.order(created_at: :desc).first
        invoice_subscription = invoice.invoice_subscriptions.first

        expect(invoice_subscription.from_datetime).to match_datetime("2024-01-31T00:00:00Z")
        expect(invoice_subscription.to_datetime).to match_datetime("2024-01-31T01:00:00Z")
        expect(invoice_subscription.charges_from_datetime).to match_datetime("2024-01-31T01:00:00Z")
        expect(invoice_subscription.charges_to_datetime).to match_datetime("2024-02-28T23:59:59Z")
        expect(invoice_subscription.fixed_charges_from_datetime).to match_datetime("2024-01-31T01:00:00Z")
        expect(invoice_subscription.fixed_charges_to_datetime).to match_datetime("2024-01-31T01:00:00Z")

        # March billing
        travel_to(Time.zone.parse("2024-03-31T02:00:00Z")) do
          expect { perform_billing }.to change { subscription.reload.invoices.count }.by(1)
        end

        invoice = subscription.invoices.order(created_at: :desc).first
        invoice_subscription = invoice.invoice_subscriptions.first

        expect(invoice_subscription.from_datetime).to match_datetime("2024-01-31T00:00:00Z")
        expect(invoice_subscription.to_datetime).to match_datetime("2024-01-31T01:00:00Z")
        expect(invoice_subscription.charges_from_datetime).to match_datetime("2024-02-29T00:00:00Z")
        expect(invoice_subscription.charges_to_datetime).to match_datetime("2024-03-30T23:59:59Z")
        expect(invoice_subscription.fixed_charges_from_datetime).to match_datetime("2024-01-31T01:00:00Z")
        expect(invoice_subscription.fixed_charges_to_datetime).to match_datetime("2024-01-31T01:00:00Z")

        # April billing
        travel_to(Time.zone.parse("2024-04-30T02:00:00Z")) do
          expect { perform_billing }.to change { subscription.reload.invoices.count }.by(1)
        end

        invoice = subscription.invoices.order(created_at: :desc).first
        invoice_subscription = invoice.invoice_subscriptions.first

        expect(invoice_subscription.from_datetime).to match_datetime("2024-01-31T00:00:00Z")
        expect(invoice_subscription.to_datetime).to match_datetime("2024-01-31T01:00:00Z")
        expect(invoice_subscription.charges_from_datetime).to match_datetime("2024-03-31T00:00:00Z")
        expect(invoice_subscription.charges_to_datetime).to match_datetime("2024-04-29T23:59:59Z")
        expect(invoice_subscription.fixed_charges_from_datetime).to match_datetime("2024-01-31T01:00:00Z")
        expect(invoice_subscription.fixed_charges_to_datetime).to match_datetime("2024-01-31T01:00:00Z")

        # next year billing
        travel_to(Time.zone.parse("2025-01-31T02:00:00Z")) do
          expect { perform_billing }.to change { subscription.reload.invoices.count }.by(1)
        end

        invoice = subscription.invoices.order(created_at: :desc).first
        invoice_subscription = invoice.invoice_subscriptions.first

        expect(invoice_subscription.from_datetime).to match_datetime("2024-01-31T00:00:00Z")
        expect(invoice_subscription.to_datetime).to match_datetime("2025-01-30T23:59:59Z")
        expect(invoice_subscription.charges_from_datetime).to match_datetime("2024-12-31T00:00:00Z")
        expect(invoice_subscription.charges_to_datetime).to match_datetime("2025-01-30T23:59:59Z")
        expect(invoice_subscription.fixed_charges_from_datetime).to match_datetime("2024-01-31T01:00:00Z")
        expect(invoice_subscription.fixed_charges_to_datetime).to match_datetime("2025-01-30T23:59:59Z")
      end
    end
  end
end

# can I add some tests here????
