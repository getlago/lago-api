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

  context "with plans in advance and all charges are in arrears" do
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
        # when only charges are billed monthly, fixed charge boundaries are nil
        expect(invoice_subscription.fixed_charges_from_datetime).to eq(nil)
        expect(invoice_subscription.fixed_charges_to_datetime).to eq(nil)

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
        expect(invoice_subscription.fixed_charges_from_datetime).to eq(nil)
        expect(invoice_subscription.fixed_charges_to_datetime).to eq(nil)

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
        expect(invoice_subscription.fixed_charges_from_datetime).to eq(nil)
        expect(invoice_subscription.fixed_charges_to_datetime).to eq(nil)

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

    context "when fixed charges are billed monthly" do
      let(:plan_monthly_fixed_charges) { true }

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
        expect(invoice_subscription.charges_from_datetime).to eq(nil)
        expect(invoice_subscription.charges_to_datetime).to eq(nil)
        expect(invoice_subscription.fixed_charges_from_datetime).to match_datetime("2024-01-31T01:00:00Z")
        expect(invoice_subscription.fixed_charges_to_datetime).to match_datetime("2024-02-28T23:59:59Z")

        # March billing
        travel_to(Time.zone.parse("2024-03-31T02:00:00Z")) do
          expect { perform_billing }.to change { subscription.reload.invoices.count }.by(1)
        end

        invoice = subscription.invoices.order(created_at: :desc).first
        invoice_subscription = invoice.invoice_subscriptions.first

        expect(invoice_subscription.from_datetime).to match_datetime("2024-01-31T00:00:00Z")
        expect(invoice_subscription.to_datetime).to match_datetime("2024-01-31T01:00:00Z")
        expect(invoice_subscription.charges_from_datetime).to eq(nil)
        expect(invoice_subscription.charges_to_datetime).to eq(nil)
        expect(invoice_subscription.fixed_charges_from_datetime).to match_datetime("2024-02-29T00:00:00Z")
        expect(invoice_subscription.fixed_charges_to_datetime).to match_datetime("2024-03-30T23:59:59Z")

        # April billing
        travel_to(Time.zone.parse("2024-04-30T02:00:00Z")) do
          expect { perform_billing }.to change { subscription.reload.invoices.count }.by(1)
        end

        invoice = subscription.invoices.order(created_at: :desc).first
        invoice_subscription = invoice.invoice_subscriptions.first

        expect(invoice_subscription.from_datetime).to match_datetime("2024-01-31T00:00:00Z")
        expect(invoice_subscription.to_datetime).to match_datetime("2024-01-31T01:00:00Z")
        expect(invoice_subscription.charges_from_datetime).to eq(nil)
        expect(invoice_subscription.charges_to_datetime).to eq(nil)
        expect(invoice_subscription.fixed_charges_from_datetime).to match_datetime("2024-03-31T00:00:00Z")
        expect(invoice_subscription.fixed_charges_to_datetime).to match_datetime("2024-04-29T23:59:59Z")

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
        expect(invoice_subscription.fixed_charges_from_datetime).to match_datetime("2024-12-31T00:00:00Z")
        expect(invoice_subscription.fixed_charges_to_datetime).to match_datetime("2025-01-30T23:59:59Z")
      end
    end

    context "when both charges and fixed charges are billed monthly" do
      let(:plan_monthly_charges) { true }
      let(:plan_monthly_fixed_charges) { true }

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
        expect(invoice_subscription.fixed_charges_to_datetime).to match_datetime("2024-02-28T23:59:59Z")

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
        expect(invoice_subscription.fixed_charges_from_datetime).to match_datetime("2024-02-29T00:00:00Z")
        expect(invoice_subscription.fixed_charges_to_datetime).to match_datetime("2024-03-30T23:59:59Z")

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
        expect(invoice_subscription.fixed_charges_from_datetime).to match_datetime("2024-12-31T00:00:00Z")
        expect(invoice_subscription.fixed_charges_to_datetime).to match_datetime("2025-01-30T23:59:59Z")
      end
    end

    context "when plan is in advance and charges are billed monthly" do
      let(:plan_in_advance) { true }
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
        expect(subscription.invoices.count).to eq(1)

        # First invoice - subscription creation (pay in advance)
        invoice = subscription.invoices.order(created_at: :desc).first
        invoice_subscription = invoice.invoice_subscriptions.first

        expect(invoice_subscription.from_datetime).to match_datetime("2024-01-31T00:00:00Z")
        expect(invoice_subscription.to_datetime).to match_datetime("2025-01-30T23:59:59Z")
        expect(invoice_subscription.charges_from_datetime).to match_datetime("2024-01-31T01:00:00Z")
        expect(invoice_subscription.charges_to_datetime).to match_datetime("2024-01-31T01:00:00Z")
        expect(invoice_subscription.fixed_charges_from_datetime).to match_datetime("2024-01-31T01:00:00Z")
        expect(invoice_subscription.fixed_charges_to_datetime).to match_datetime("2024-01-31T01:00:00Z")

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

        # February billing - second invoice (charges only)
        travel_to(Time.zone.parse("2024-02-29T02:00:00Z")) do
          expect { perform_billing }.to change { subscription.reload.invoices.count }.by(1)
        end

        invoice = subscription.invoices.order(created_at: :desc).first
        invoice_subscription = invoice.invoice_subscriptions.first

        expect(invoice_subscription.from_datetime).to match_datetime("2024-01-31T00:00:00Z")
        expect(invoice_subscription.to_datetime).to match_datetime("2025-01-30T23:59:59Z")
        expect(invoice_subscription.charges_from_datetime).to match_datetime("2024-01-31T01:00:00Z")
        expect(invoice_subscription.charges_to_datetime).to match_datetime("2024-02-28T23:59:59Z")
        expect(invoice_subscription.fixed_charges_from_datetime).to eq(nil)
        expect(invoice_subscription.fixed_charges_to_datetime).to eq(nil)

        # next year billing
        travel_to(Time.zone.parse("2025-01-31T02:00:00Z")) do
          expect { perform_billing }.to change { subscription.reload.invoices.count }.by(1)
        end

        invoice = subscription.invoices.order(created_at: :desc).first
        invoice_subscription = invoice.invoice_subscriptions.first

        expect(invoice_subscription.from_datetime).to match_datetime("2025-01-31T00:00:00Z")
        expect(invoice_subscription.to_datetime).to match_datetime("2026-01-30T23:59:59Z")
        expect(invoice_subscription.charges_from_datetime).to match_datetime("2024-12-31T00:00:00Z")
        expect(invoice_subscription.charges_to_datetime).to match_datetime("2025-01-30T23:59:59Z")
        expect(invoice_subscription.fixed_charges_from_datetime).to match_datetime("2024-01-31T01:00:00Z")
        expect(invoice_subscription.fixed_charges_to_datetime).to match_datetime("2025-01-30T23:59:59Z")
      end
    end

    context "when plan is in advance and fixed charges are billed monthly" do
      let(:plan_in_advance) { true }
      let(:plan_monthly_fixed_charges) { true }

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
        expect(subscription.invoices.count).to eq(1)

        # First invoice - subscription creation (pay in advance)
        invoice = subscription.invoices.order(created_at: :desc).first
        invoice_subscription = invoice.invoice_subscriptions.first

        expect(invoice_subscription.from_datetime).to match_datetime("2024-01-31T00:00:00Z")
        expect(invoice_subscription.to_datetime).to match_datetime("2025-01-30T23:59:59Z")
        expect(invoice_subscription.charges_from_datetime).to match_datetime("2024-01-31T01:00:00Z")
        expect(invoice_subscription.charges_to_datetime).to match_datetime("2024-01-31T01:00:00Z")
        expect(invoice_subscription.fixed_charges_from_datetime).to match_datetime("2024-01-31T01:00:00Z")
        expect(invoice_subscription.fixed_charges_to_datetime).to match_datetime("2024-01-31T01:00:00Z")

        # February billing - second invoice (fixed charges only)
        travel_to(Time.zone.parse("2024-02-29T02:00:00Z")) do
          expect { perform_billing }.to change { subscription.reload.invoices.count }.by(1)
        end

        invoice = subscription.invoices.order(created_at: :desc).first
        invoice_subscription = invoice.invoice_subscriptions.first

        expect(invoice_subscription.from_datetime).to match_datetime("2024-01-31T00:00:00Z")
        expect(invoice_subscription.to_datetime).to match_datetime("2025-01-30T23:59:59Z")
        expect(invoice_subscription.charges_from_datetime).to eq(nil)
        expect(invoice_subscription.charges_to_datetime).to eq(nil)
        expect(invoice_subscription.fixed_charges_from_datetime).to match_datetime("2024-01-31T01:00:00Z")
        expect(invoice_subscription.fixed_charges_to_datetime).to match_datetime("2024-02-28T23:59:59Z")

        # next year billing
        travel_to(Time.zone.parse("2025-01-31T02:00:00Z")) do
          expect { perform_billing }.to change { subscription.reload.invoices.count }.by(1)
        end

        invoice = subscription.invoices.order(created_at: :desc).first
        invoice_subscription = invoice.invoice_subscriptions.first

        expect(invoice_subscription.from_datetime).to match_datetime("2025-01-31T00:00:00Z")
        expect(invoice_subscription.to_datetime).to match_datetime("2026-01-30T23:59:59Z")
        expect(invoice_subscription.charges_from_datetime).to match_datetime("2024-01-31T01:00:00Z")
        expect(invoice_subscription.charges_to_datetime).to match_datetime("2025-01-30T23:59:59Z")
        expect(invoice_subscription.fixed_charges_from_datetime).to match_datetime("2024-12-31T00:00:00Z")
        expect(invoice_subscription.fixed_charges_to_datetime).to match_datetime("2025-01-30T23:59:59Z")
      end
    end
  end

  context "when interval is semiannual" do
    let(:plan_interval) { :semiannual }

    it "creates invoices twice a year" do
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

      # May billing
      travel_to(Time.zone.parse("2024-05-31T02:00:00Z")) do
        expect { perform_billing }.not_to change { subscription.reload.invoices.count }
      end

      # June billing
      travel_to(Time.zone.parse("2024-06-30T02:00:00Z")) do
        expect { perform_billing }.not_to change { subscription.reload.invoices.count }
      end

      # July billing
      travel_to(Time.zone.parse("2024-07-31T02:00:00Z")) do
        expect { perform_billing }.to change { subscription.reload.invoices.count }.by(1)
      end

      invoice = subscription.invoices.order(created_at: :desc).first
      invoice_subscription = invoice.invoice_subscriptions.first

      expect(invoice_subscription.from_datetime).to match_datetime("2024-01-31T00:00:00Z")
      expect(invoice_subscription.to_datetime).to match_datetime("2024-07-30T23:59:59Z")
      expect(invoice_subscription.charges_from_datetime).to match_datetime("2024-01-31T01:00:00Z")
      expect(invoice_subscription.charges_to_datetime).to match_datetime("2024-07-30T23:59:59Z")
      expect(invoice_subscription.fixed_charges_from_datetime).to match_datetime("2024-01-31T01:00:00Z")
      expect(invoice_subscription.fixed_charges_to_datetime).to match_datetime("2024-07-30T23:59:59Z")

      # August billing
      travel_to(Time.zone.parse("2024-08-30T02:00:00Z")) do
        expect { perform_billing }.not_to change { subscription.reload.invoices.count }
      end

      # Next year Jan billing
      travel_to(Time.zone.parse("2025-01-31T02:00:00Z")) do
        expect { perform_billing }.to change { subscription.reload.invoices.count }.by(1)
      end

      invoice = subscription.invoices.order(created_at: :desc).first
      invoice_subscription = invoice.invoice_subscriptions.first

      expect(invoice_subscription.from_datetime).to match_datetime("2024-07-31T00:00:00Z")
      expect(invoice_subscription.to_datetime).to match_datetime("2025-01-30T23:59:59Z")
      expect(invoice_subscription.charges_from_datetime).to match_datetime("2024-07-31T00:00:00Z")
      expect(invoice_subscription.charges_to_datetime).to match_datetime("2025-01-30T23:59:59Z")
      expect(invoice_subscription.fixed_charges_from_datetime).to match_datetime("2024-07-31T00:00:00Z")
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
        # TODO: only in semiannual these dates are not following the behaviour where previous billing period is provided.
        # expect(invoice_subscription.to_datetime).to match_datetime("2024-01-31T01:00:00Z")
        expect(invoice_subscription.charges_from_datetime).to match_datetime("2024-01-31T01:00:00Z")
        expect(invoice_subscription.charges_to_datetime).to match_datetime("2024-02-28T23:59:59Z")
        expect(invoice_subscription.fixed_charges_from_datetime).to eq(nil)
        # TODO: only in semiannual these dates are not following the behaviour where previous billing period is provided.
        # expect(invoice_subscription.fixed_charges_to_datetime).to eq(nil)

        # March billing
        travel_to(Time.zone.parse("2024-03-31T02:00:00Z")) do
          expect { perform_billing }.to change { subscription.reload.invoices.count }.by(1)
        end

        invoice = subscription.invoices.order(created_at: :desc).first
        invoice_subscription = invoice.invoice_subscriptions.first

        expect(invoice_subscription.from_datetime).to match_datetime("2024-01-31T00:00:00Z")
        # TODO: only in semiannual these dates are not following the behaviour where previous billing period is provided.
        # expect(invoice_subscription.to_datetime).to match_datetime("2024-01-31T01:00:00Z")
        expect(invoice_subscription.charges_from_datetime).to match_datetime("2024-02-29T00:00:00Z")
        expect(invoice_subscription.charges_to_datetime).to match_datetime("2024-03-30T23:59:59Z")
        expect(invoice_subscription.fixed_charges_from_datetime).to eq(nil)
        # TODO: only in semiannual these dates are not following the behaviour where previous billing period is provided.
        # expect(invoice_subscription.fixed_charges_to_datetime).to eq(nil)

        # July billing
        travel_to(Time.zone.parse("2024-07-31T02:00:00Z")) do
          expect { perform_billing }.to change { subscription.reload.invoices.count }.by(1)
        end

        invoice = subscription.invoices.order(created_at: :desc).first
        invoice_subscription = invoice.invoice_subscriptions.first

        expect(invoice_subscription.from_datetime).to match_datetime("2024-01-31T00:00:00Z")
        expect(invoice_subscription.to_datetime).to match_datetime("2024-07-30T23:59:59Z")
        expect(invoice_subscription.charges_from_datetime).to match_datetime("2024-06-30T00:00:00Z")
        expect(invoice_subscription.charges_to_datetime).to match_datetime("2024-07-30T23:59:59Z")
        expect(invoice_subscription.fixed_charges_from_datetime).to match_datetime("2024-01-31T01:00:00Z")
        expect(invoice_subscription.fixed_charges_to_datetime).to match_datetime("2024-07-30T23:59:59Z")
      end
    end

    context "when fixed charges are billed monthly" do
      let(:plan_monthly_fixed_charges) { true }

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
        expect(invoice_subscription.charges_from_datetime).to eq(nil)
        expect(invoice_subscription.charges_to_datetime).to eq(nil)
        expect(invoice_subscription.fixed_charges_from_datetime).to match_datetime("2024-01-31T01:00:00Z")
        expect(invoice_subscription.fixed_charges_to_datetime).to match_datetime("2024-02-28T23:59:59Z")

        # March billing
        travel_to(Time.zone.parse("2024-03-31T02:00:00Z")) do
          expect { perform_billing }.to change { subscription.reload.invoices.count }.by(1)
        end

        invoice = subscription.invoices.order(created_at: :desc).first
        invoice_subscription = invoice.invoice_subscriptions.first

        expect(invoice_subscription.from_datetime).to match_datetime("2024-01-31T00:00:00Z")
        expect(invoice_subscription.charges_from_datetime).to eq(nil)
        expect(invoice_subscription.charges_to_datetime).to eq(nil)
        expect(invoice_subscription.fixed_charges_from_datetime).to match_datetime("2024-02-29T00:00:00Z")
        expect(invoice_subscription.fixed_charges_to_datetime).to match_datetime("2024-03-30T23:59:59Z")

        # July billing
        travel_to(Time.zone.parse("2024-07-31T02:00:00Z")) do
          expect { perform_billing }.to change { subscription.reload.invoices.count }.by(1)
        end

        invoice = subscription.invoices.order(created_at: :desc).first
        invoice_subscription = invoice.invoice_subscriptions.first

        expect(invoice_subscription.from_datetime).to match_datetime("2024-01-31T00:00:00Z")
        expect(invoice_subscription.to_datetime).to match_datetime("2024-07-30T23:59:59Z")
        expect(invoice_subscription.charges_from_datetime).to match_datetime("2024-01-31T01:00:00Z")
        expect(invoice_subscription.charges_to_datetime).to match_datetime("2024-07-30T23:59:59Z")
        expect(invoice_subscription.fixed_charges_from_datetime).to match_datetime("2024-06-30T00:00:00Z")
        expect(invoice_subscription.fixed_charges_to_datetime).to match_datetime("2024-07-30T23:59:59Z")
      end
    end

    context "when both charges and fixed charges are billed monthly" do
      let(:plan_monthly_charges) { true }
      let(:plan_monthly_fixed_charges) { true }

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

        expect(invoice_subscription.from_datetime).to match_datetime("2024-01-31T00:00:00Z")
        expect(invoice_subscription.charges_from_datetime).to match_datetime("2024-02-29T00:00:00Z")
        expect(invoice_subscription.charges_to_datetime).to match_datetime("2024-03-30T23:59:59Z")
        expect(invoice_subscription.fixed_charges_from_datetime).to match_datetime("2024-02-29T00:00:00Z")
        expect(invoice_subscription.fixed_charges_to_datetime).to match_datetime("2024-03-30T23:59:59Z")

        # July billing
        travel_to(Time.zone.parse("2024-07-31T02:00:00Z")) do
          expect { perform_billing }.to change { subscription.reload.invoices.count }.by(1)
        end

        invoice = subscription.invoices.order(created_at: :desc).first
        invoice_subscription = invoice.invoice_subscriptions.first

        expect(invoice_subscription.from_datetime).to match_datetime("2024-01-31T00:00:00Z")
        expect(invoice_subscription.to_datetime).to match_datetime("2024-07-30T23:59:59Z")
        expect(invoice_subscription.charges_from_datetime).to match_datetime("2024-06-30T00:00:00Z")
        expect(invoice_subscription.charges_to_datetime).to match_datetime("2024-07-30T23:59:59Z")
        expect(invoice_subscription.fixed_charges_from_datetime).to match_datetime("2024-06-30T00:00:00Z")
        expect(invoice_subscription.fixed_charges_to_datetime).to match_datetime("2024-07-30T23:59:59Z")
      end
    end

    context "when plan is in advance and charges are billed monthly" do
      let(:plan_in_advance) { true }
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
        expect(subscription.invoices.count).to eq(1)

        # First invoice - subscription creation (pay in advance)
        invoice = subscription.invoices.order(created_at: :desc).first
        invoice_subscription = invoice.invoice_subscriptions.first

        expect(invoice_subscription.from_datetime).to match_datetime("2024-01-31T00:00:00Z")
        expect(invoice_subscription.to_datetime).to match_datetime("2024-07-30T23:59:59Z")
        expect(invoice_subscription.charges_from_datetime).to match_datetime("2024-01-31T01:00:00Z")
        expect(invoice_subscription.charges_to_datetime).to match_datetime("2024-01-31T01:00:00Z")
        expect(invoice_subscription.fixed_charges_from_datetime).to match_datetime("2024-01-31T01:00:00Z")
        expect(invoice_subscription.fixed_charges_to_datetime).to match_datetime("2024-01-31T01:00:00Z")

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

        # February billing - second invoice (charges only)
        travel_to(Time.zone.parse("2024-02-29T02:00:00Z")) do
          expect { perform_billing }.to change { subscription.reload.invoices.count }.by(1)
        end

        invoice = subscription.invoices.order(created_at: :desc).first
        invoice_subscription = invoice.invoice_subscriptions.first

        expect(invoice_subscription.from_datetime).to match_datetime("2024-02-29T00:00:00Z")
        expect(invoice_subscription.charges_from_datetime).to match_datetime("2024-01-31T01:00:00Z")
        expect(invoice_subscription.charges_to_datetime).to match_datetime("2024-02-28T23:59:59Z")
        expect(invoice_subscription.fixed_charges_from_datetime).to eq(nil)
        expect(invoice_subscription.fixed_charges_to_datetime).to eq(nil)

        # July billing (6 months after subscription started)
        travel_to(Time.zone.parse("2024-07-31T02:00:00Z")) do
          expect { perform_billing }.to change { subscription.reload.invoices.count }.by(1)
        end

        invoice = subscription.invoices.order(created_at: :desc).first
        invoice_subscription = invoice.invoice_subscriptions.first

        expect(invoice_subscription.from_datetime).to match_datetime("2024-07-31T00:00:00Z")
        expect(invoice_subscription.to_datetime).to match_datetime("2025-01-30T23:59:59Z")
        expect(invoice_subscription.charges_from_datetime).to match_datetime("2024-06-30T00:00:00Z")
        expect(invoice_subscription.charges_to_datetime).to match_datetime("2024-07-30T23:59:59Z")
        expect(invoice_subscription.fixed_charges_from_datetime).to match_datetime("2024-01-31T01:00:00Z")
        expect(invoice_subscription.fixed_charges_to_datetime).to match_datetime("2024-07-30T23:59:59Z")
      end
    end

    context "when plan is in advance and fixed charges are billed monthly" do
      let(:plan_in_advance) { true }
      let(:plan_monthly_fixed_charges) { true }

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
        expect(subscription.invoices.count).to eq(1)

        # First invoice - subscription creation (pay in advance)
        invoice = subscription.invoices.order(created_at: :desc).first
        invoice_subscription = invoice.invoice_subscriptions.first

        expect(invoice_subscription.from_datetime).to match_datetime("2024-01-31T00:00:00Z")
        expect(invoice_subscription.to_datetime).to match_datetime("2024-07-30T23:59:59Z")

        # February billing - second invoice (fixed charges only)
        travel_to(Time.zone.parse("2024-02-29T02:00:00Z")) do
          expect { perform_billing }.to change { subscription.reload.invoices.count }.by(1)
        end

        invoice = subscription.invoices.order(created_at: :desc).first
        invoice_subscription = invoice.invoice_subscriptions.first

        expect(invoice_subscription.from_datetime).to match_datetime("2024-02-29T00:00:00Z")
        expect(invoice_subscription.charges_from_datetime).to eq(nil)
        expect(invoice_subscription.charges_to_datetime).to eq(nil)
        expect(invoice_subscription.fixed_charges_from_datetime).to match_datetime("2024-01-31T01:00:00Z")
        expect(invoice_subscription.fixed_charges_to_datetime).to match_datetime("2024-02-28T23:59:59Z")

        # July billing (6 months after subscription started)
        travel_to(Time.zone.parse("2024-07-31T02:00:00Z")) do
          expect { perform_billing }.to change { subscription.reload.invoices.count }.by(1)
        end

        invoice = subscription.invoices.order(created_at: :desc).first
        invoice_subscription = invoice.invoice_subscriptions.first

        expect(invoice_subscription.from_datetime).to match_datetime("2024-07-31T00:00:00Z")
        expect(invoice_subscription.to_datetime).to match_datetime("2025-01-30T23:59:59Z")
        expect(invoice_subscription.charges_from_datetime).to match_datetime("2024-01-31T01:00:00Z")
        expect(invoice_subscription.charges_to_datetime).to match_datetime("2024-07-30T23:59:59Z")
        expect(invoice_subscription.fixed_charges_from_datetime).to match_datetime("2024-06-30T00:00:00Z")
        expect(invoice_subscription.fixed_charges_to_datetime).to match_datetime("2024-07-30T23:59:59Z")
      end
    end
  end

  context "when interval is quarterly" do
    let(:plan_interval) { :quarterly }

    it "creates invoices four times a year" do
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
        expect { perform_billing }.to change { subscription.reload.invoices.count }.by(1)
      end

      invoice = subscription.invoices.order(created_at: :desc).first
      invoice_subscription = invoice.invoice_subscriptions.first

      expect(invoice_subscription.from_datetime).to match_datetime("2024-01-31T00:00:00Z")
      expect(invoice_subscription.to_datetime).to match_datetime("2024-04-29T23:59:59Z")
      expect(invoice_subscription.charges_from_datetime).to match_datetime("2024-01-31T01:00:00Z")
      expect(invoice_subscription.charges_to_datetime).to match_datetime("2024-04-29T23:59:59Z")
      expect(invoice_subscription.fixed_charges_from_datetime).to match_datetime("2024-01-31T01:00:00Z")
      expect(invoice_subscription.fixed_charges_to_datetime).to match_datetime("2024-04-29T23:59:59Z")

      # May billing
      travel_to(Time.zone.parse("2024-05-31T02:00:00Z")) do
        expect { perform_billing }.not_to change { subscription.reload.invoices.count }
      end

      # June billing
      travel_to(Time.zone.parse("2024-06-30T02:00:00Z")) do
        expect { perform_billing }.not_to change { subscription.reload.invoices.count }
      end

      # July billing
      travel_to(Time.zone.parse("2024-07-31T02:00:00Z")) do
        expect { perform_billing }.to change { subscription.reload.invoices.count }.by(1)
      end

      invoice = subscription.invoices.order(created_at: :desc).first
      invoice_subscription = invoice.invoice_subscriptions.first

      expect(invoice_subscription.from_datetime).to match_datetime("2024-04-30T00:00:00Z")
      expect(invoice_subscription.to_datetime).to match_datetime("2024-07-30T23:59:59Z")
      expect(invoice_subscription.charges_from_datetime).to match_datetime("2024-04-30T00:00:00Z")
      expect(invoice_subscription.charges_to_datetime).to match_datetime("2024-07-30T23:59:59Z")
      expect(invoice_subscription.fixed_charges_from_datetime).to match_datetime("2024-04-30T00:00:00Z")
      expect(invoice_subscription.fixed_charges_to_datetime).to match_datetime("2024-07-30T23:59:59Z")
    end
    # NOTE: there are no quarterly with charges monthly!
  end
end
