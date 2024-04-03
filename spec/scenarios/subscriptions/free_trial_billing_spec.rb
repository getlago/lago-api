# frozen_string_literal: true

require 'rails_helper'

describe 'Free Trial Billing Subscriptions Scenario', :scenarios, type: :request do
  let(:organization) { create(:organization, webhook_url: nil) }

  let(:timezone) { 'UTC' }
  let(:customer) { create(:customer, organization:, timezone:) }

  let(:plan) do
    create(
      :plan,
      organization:,
      trial_period:,
      amount_cents: 5_000_000,
      pay_in_advance: true,
    )
  end

  context 'without free trial' do
    let(:trial_period) { 0 }

    it 'bills the customer at the beginning of the subscription' do
      travel_to(Time.zone.parse('2024-03-05T12:12:00')) do
        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: customer.external_id,
            plan_code: plan.code,
          },
        )

        expect(customer.reload.invoices.count).to eq(1)
        expect(customer.invoices.first.fees.subscription).to exist
      end
    end
  end

  context 'with free trial' do
    let(:trial_period) { 10 }

    it 'bills the customer at the end of the free trial' do
      travel_to(Time.zone.parse('2024-03-05T12:12:00')) do
        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: customer.external_id,
            plan_code: plan.code,
          },
        )

        expect(customer.reload.invoices.count).to eq(0)
      end
      subscription = customer.subscriptions.sole

      # Ensure nothing happened
      travel_to(Time.zone.parse('2024-03-10T12:12:00')) do
        perform_billing
        expect(customer.reload.invoices.count).to eq(0)
      end

      # NOTE: The subscription was started at 12:12:00, so the trial period ends exactly at 12:12:00
      #       This ensure that Subscriptions::FreeTrialBillingService grabs subscriptions that
      #       ended in the last hour.
      travel_to(Time.zone.parse('2024-03-15T12:02:00')) do
        expect(subscription).to be_in_trial_period
        perform_billing
        expect(customer.reload.invoices.count).to eq(0)
      end

      travel_to(Time.zone.parse('2024-03-15T13:02:00')) do
        expect(subscription).not_to be_in_trial_period
        perform_billing
        expect(customer.reload.invoices.count).to eq(1)
        invoice = customer.reload.invoices.sole
        expect(invoice.fees.count).to eq(1)
        expect(invoice.fees.subscription.first.amount_cents).to eq(2_741_935) # (31 - 4 - 10) / 31 * 5000000 = 2741935
      end
    end

    # NOTE: This only happens if the customer was billed at the beginning of the free trial
    #       BEFORE the feature to bill at the end of the free trial was implemented
    it 'does not bill the customer if it was already billed at the beginning of the trial' do
      travel_to(Time.zone.parse('2024-03-05T12:12:00')) do
        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: customer.external_id,
            plan_code: plan.code,
          },
        )

        expect(customer.reload.invoices.count).to eq(0)

        plan.update! trial_period: 0 # disable trial to force billing
        BillSubscriptionJob.perform_now(customer.subscriptions, Time.current)

        expect(customer.reload.invoices.count).to eq(1)

        plan.update! trial_period: 10
      end

      # Ensure nothing happened
      travel_to(Time.zone.parse('2024-03-10T12:12:00')) do
        perform_billing
        expect(customer.reload.invoices.count).to eq(1)
      end

      travel_to(Time.zone.parse('2024-03-15T15:00:00')) do
        perform_billing
        expect(customer.reload.invoices.count).to eq(1)
      end

      travel_to(Time.zone.parse('2024-03-20T12:12:00')) do
        perform_billing
        expect(customer.reload.invoices.count).to eq(1)
      end
    end
  end

  context 'with free trial > billing period' do
    let(:trial_period) { 45 }
    let(:billable_metric) { create(:billable_metric, organization:) }

    it 'bills subscription at the end of the free trial' do
      travel_to(Time.zone.parse('2024-03-05T12:12:00')) do
        create(:standard_charge, plan:, billable_metric:, properties: { amount: '10' })
        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: customer.external_id,
            plan_code: plan.code,
          },
        )

        expect(customer.reload.invoices.count).to eq(0)
      end

      travel_to(Time.zone.parse('2024-03-10')) do
        create_event(
          {
            code: billable_metric.code,
            transaction_id: SecureRandom.uuid,
            external_customer_id: customer.external_id,
          },
        )
      end

      travel_to(Time.zone.parse('2024-04-01')) do
        perform_billing
        expect(customer.reload.invoices.count).to eq(1)
      end

      invoice = customer.invoices.first
      expect(invoice.fees.subscription).not_to exist
      expect(invoice.fees.charge.first.amount_cents).to eq(1000)

      travel_to(Time.zone.parse('2024-04-19T13:01:00')) do
        perform_billing
        expect(customer.reload.invoices.count).to eq(2)
      end

      free_trial_invoice = customer.invoices.order(created_at: :desc).first
      expect(free_trial_invoice.fees.subscription.first.amount_cents).to eq(2_000_000) # 5_000_000 * 12 / 30
      expect(free_trial_invoice.fees.charge).not_to exist
    end
  end

  context 'with free trial ending on billing day' do
    let(:trial_period) { 10 }
    let(:billable_metric) { create(:billable_metric, organization:) }

    it 'bills subscription and usage-based charges' do
      start_time = Time.zone.parse('2024-03-22T12:12:00')
      travel_to(start_time) do
        create(:standard_charge, plan:, billable_metric:, properties: { amount: '10' })
        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: customer.external_id,
            plan_code: plan.code,
          },
        )

        expect(customer.reload.invoices.count).to eq(0)
      end

      travel_to(Time.zone.parse('2024-03-23')) do
        create_event(
          {
            code: billable_metric.code,
            transaction_id: SecureRandom.uuid,
            external_customer_id: customer.external_id,
          },
        )
      end

      expect(customer.reload.invoices.count).to eq(0)

      # NOTE: Subscriptions::BillingService will bill the subscription because it's billing day
      #       Subscriptions::FreeTrialBillingService will ignore it because the trial ends at 12:12:00
      travel_to(Time.zone.parse('2024-04-01')) do
        perform_billing
        invoice = customer.invoices.order(created_at: :desc).sole
        expect(invoice.fees.subscription.first.amount_cents).to eq(5_000_000) # full fee, trial is over
        expect(invoice.fees.charge.first.amount_cents).to eq(1000)
      end

      # NOTE: After the trial ends, we don't invoice again because it was done above
      #       but we terminate the trial and send the webhook
      travel_to(Time.zone.parse('2024-04-01T13:11:00')) do
        perform_billing
        expect(customer.reload.invoices.count).to eq(1)
        expect(customer.subscriptions.sole.trial_ended_at).to be_within(1.minute).of(start_time + trial_period.days)
      end
    end
  end
end
