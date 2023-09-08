# frozen_string_literal: true

require 'rails_helper'

describe 'Subscriptions Termination Scenario', :scenarios, type: :request do
  let(:organization) { create(:organization, webhook_url: nil) }

  let(:timezone) { 'Europe/Paris' }
  let(:customer) { create(:customer, organization:, timezone:) }

  let(:plan) do
    create(
      :plan,
      organization:,
      interval: 'monthly',
      amount_cents: 1000,
      pay_in_advance: false,
    )
  end

  let(:creation_time) { DateTime.new(2023, 9, 5, 0, 0) }
  let(:subscription_at) { DateTime.new(2023, 9, 5, 0, 0) }
  let(:ending_at) { DateTime.new(2023, 9, 6, 0, 0) }

  context 'when timezone is Europe/Paris' do
    it 'terminates the subscription when it reaches its ending date' do
      subscription = nil

      travel_to(creation_time) do
        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: customer.external_id,
            plan_code: plan.code,
            billing_time: 'anniversary',
            subscription_at: subscription_at.iso8601,
            ending_at: ending_at.iso8601,
          },
        )

        subscription = customer.subscriptions.first
        expect(subscription).to be_active
      end

      travel_to(ending_at + 15.minutes) do
        Clock::TerminateEndedSubscriptionsJob.perform_now

        perform_all_enqueued_jobs

        invoice = subscription.invoices.first

        aggregate_failures do
          expect(subscription.reload).to be_terminated
          expect(subscription.reload.invoices.count).to eq(1)
          expect(invoice.total_amount_cents).to eq(67) # 1000 / 30
          expect(invoice.issuing_date.iso8601).to eq('2023-09-06')
        end
      end
    end
  end

  context 'when timezone is Asia/Bangkok' do
    let(:timezone) { 'Asia/Bangkok' }
    let(:creation_time) { DateTime.new(2023, 9, 5, 0, 0) }
    let(:subscription_at) { DateTime.new(2023, 9, 5, 0, 0) }
    let(:ending_at) { DateTime.new(2023, 9, 6, 0, 0) }

    it 'terminates the subscription when it reaches its ending date' do
      subscription = nil

      travel_to(creation_time) do
        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: customer.external_id,
            plan_code: plan.code,
            billing_time: 'anniversary',
            subscription_at: subscription_at.iso8601,
            ending_at: ending_at.iso8601,
          },
        )

        subscription = customer.subscriptions.first
        expect(subscription).to be_active
      end

      travel_to(ending_at + 15.minutes) do
        Clock::TerminateEndedSubscriptionsJob.perform_now

        perform_all_enqueued_jobs

        invoice = subscription.invoices.first

        aggregate_failures do
          expect(subscription.reload).to be_terminated
          expect(subscription.reload.invoices.count).to eq(1)
          expect(invoice.total_amount_cents).to eq(67) # 1000 / 30
          expect(invoice.issuing_date.iso8601).to eq('2023-09-06')
        end
      end
    end
  end

  context 'when timezone is America/Bogota' do
    let(:timezone) { 'America/Bogota' }

    it 'terminates the subscription when it reaches its ending date' do
      subscription = nil

      travel_to(creation_time) do
        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: customer.external_id,
            plan_code: plan.code,
            billing_time: 'anniversary',
            subscription_at: subscription_at.iso8601,
            ending_at: ending_at.iso8601,
          },
        )

        subscription = customer.subscriptions.first
        expect(subscription).to be_active
      end

      travel_to(ending_at + 15.minutes) do
        Clock::TerminateEndedSubscriptionsJob.perform_now

        perform_all_enqueued_jobs

        invoice = subscription.invoices.first

        aggregate_failures do
          expect(subscription.reload).to be_terminated
          expect(subscription.reload.invoices.count).to eq(1)
          expect(invoice.total_amount_cents).to eq(67) # 1000 / 30
          expect(invoice.issuing_date.iso8601).to eq('2023-09-05')
        end
      end
    end
  end
end
