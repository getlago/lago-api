# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Subscriptions::TerminateService do
  subject(:terminate_service) { described_class.new(subscription:) }

  describe '.terminate' do
    let(:subscription) { create(:subscription) }

    it 'terminates a subscription' do
      result = terminate_service.call

      aggregate_failures do
        expect(result.subscription).to be_present
        expect(result.subscription).to be_terminated
        expect(result.subscription.terminated_at).to be_present
      end
    end

    it 'enqueues a BillSubscriptionJob' do
      expect do
        terminate_service.call
      end.to have_enqueued_job(BillSubscriptionJob)
    end

    it 'enqueues a SendWebhookJob' do
      expect do
        terminate_service.call
      end.to have_enqueued_job(SendWebhookJob)
    end

    context 'when subscription is starting in the future' do
      let(:subscription) { create(:pending_subscription) }

      it 'does not enqueue a BillSubscriptionJob' do
        expect do
          terminate_service.call
        end.not_to have_enqueued_job(BillSubscriptionJob)
      end
    end

    context 'when downgrade subscription is pending' do
      let(:subscription) { create(:pending_subscription, previous_subscription: create(:subscription)) }

      it 'does cancel it' do
        result = terminate_service.call

        aggregate_failures do
          expect(result.subscription).to be_present
          expect(result.subscription).to be_canceled
          expect(result.subscription.canceled_at).to be_present
        end
      end
    end

    context 'when subscription is not found' do
      let(:subscription) { nil }

      it 'returns an error' do
        result = terminate_service.call

        expect(result.error.error_code).to eq('subscription_not_found')
      end
    end

    context 'when pending next subscription' do
      let(:subscription) { create(:subscription) }
      let(:next_subscription) do
        create(
          :subscription,
          previous_subscription: subscription,
          status: :pending,
        )
      end

      before { next_subscription }

      it 'cancels the next subscription' do
        result = terminate_service.call

        aggregate_failures do
          expect(result).to be_success
          expect(next_subscription.reload).to be_canceled
        end
      end
    end

    context 'when subscription was payed in advance' do
      let(:creation_time) { Time.current.beginning_of_month - 1.month }
      let(:date_service) do
        Subscriptions::DatesService.new_instance(
          subscription,
          Time.current.beginning_of_month,
          current_usage: false,
        )
      end
      let(:invoice_subscription) do
        create(
          :invoice_subscription,
          invoice:,
          subscription:,
          recurring: true,
          from_datetime: date_service.from_datetime,
          to_datetime: date_service.to_datetime,
          charges_from_datetime: date_service.charges_from_datetime,
          charges_to_datetime: date_service.charges_to_datetime,
        )
      end
      let(:invoice) do
        create(
          :invoice,
          customer: subscription.customer,
          currency: 'EUR',
          sub_total_excluding_taxes_amount_cents: 100,
          fees_amount_cents: 100,
          taxes_amount_cents: 20,
          total_amount_cents: 120,
        )
      end

      let(:last_subscription_fee) do
        create(
          :fee,
          subscription:,
          invoice:,
          amount_cents: 100,
          taxes_amount_cents: 20,
          invoiceable_type: 'Subscription',
          invoiceable_id: subscription.id,
          taxes_rate: 20,
        )
      end

      before do
        subscription.plan.update!(pay_in_advance: true)
        subscription.update!(
          billing_time: :anniversary,
          started_at: creation_time,
          subscription_at: creation_time,
        )

        invoice_subscription
        last_subscription_fee
      end

      it 'creates a credit note for the remaining days' do
        expect do
          terminate_service.call
        end.to change(CreditNote, :count)
      end

      context 'when invoice subscription is not generated' do
        let(:invoice_subscription) { nil }

        it 'does not create a credit note for the remaining days' do
          expect do
            terminate_service.call
          end.not_to change(CreditNote, :count)
        end
      end
    end
  end

  describe '.terminate_and_start_next' do
    let(:subscription) { create(:subscription) }
    let(:next_subscription) { create(:subscription, previous_subscription_id: subscription.id, status: :pending) }
    let(:timestamp) { Time.zone.now.to_i }

    before { next_subscription }

    it 'terminates the subscription' do
      result = terminate_service.terminate_and_start_next(timestamp:)

      aggregate_failures do
        expect(result).to be_success
        expect(subscription.reload).to be_terminated
      end
    end

    it 'starts the next subscription' do
      result = terminate_service.terminate_and_start_next(timestamp:)

      aggregate_failures do
        expect(result).to be_success
        expect(result.subscription.id).to eq(next_subscription.id)
        expect(result.subscription).to be_active
      end
    end

    it 'enqueues a SendWebhookJob' do
      terminate_service.terminate_and_start_next(timestamp:)
      expect(SendWebhookJob).to have_been_enqueued.with('subscription.terminated', subscription)
      expect(SendWebhookJob).to have_been_enqueued.with('subscription.started', next_subscription)
    end

    context 'when terminated subscription is payed in arrear' do
      before { subscription.plan.update!(pay_in_advance: false) }

      it 'enqueues a job to bill the existing subscription' do
        expect do
          terminate_service.terminate_and_start_next(timestamp:)
        end.to have_enqueued_job(BillSubscriptionJob)
      end
    end

    context 'when next subscription is payed in advance' do
      let(:plan) { create(:plan, pay_in_advance: true) }
      let(:next_subscription) do
        create(
          :subscription,
          previous_subscription_id: subscription.id,
          plan:,
          status: :pending,
        )
      end

      before { subscription.plan.update!(pay_in_advance: true) }

      it 'enqueues one job' do
        terminate_service.terminate_and_start_next(timestamp:)

        expect(BillSubscriptionJob).to have_been_enqueued
          .with([subscription, next_subscription], timestamp)
      end
    end
  end
end
