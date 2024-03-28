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

      # Ensure nothing happened
      travel_to(Time.zone.parse('2024-03-10T12:12:00')) do
        perform_billing
        expect(customer.reload.invoices.count).to eq(0)
      end

      travel_to(Time.zone.parse('2024-03-15T15:00:00')) do
        perform_billing
        expect(customer.reload.invoices.count).to eq(1)
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
end
