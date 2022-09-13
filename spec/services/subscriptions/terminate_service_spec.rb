# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Subscriptions::TerminateService do
  subject(:terminate_service) { described_class.new }

  describe '.terminate' do
    let(:subscription) { create(:subscription) }

    it 'terminates a subscription' do
      result = terminate_service.terminate(subscription.id)

      aggregate_failures do
        expect(result.subscription).to be_present
        expect(result.subscription).to be_terminated
        expect(result.subscription.terminated_at).to be_present
      end
    end

    it 'enqueues a BillSubscriptionJob' do
      expect do
        terminate_service.terminate(subscription.id)
      end.to have_enqueued_job(BillSubscriptionJob)
    end

    context 'when subscription is not found' do
      let(:subscription) { OpenStruct.new(id: '123456') }

      it 'returns an error' do
        result = terminate_service.terminate(subscription.id)

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
        result = terminate_service.terminate(subscription.id)

        aggregate_failures do
          expect(result).to be_success
          expect(next_subscription.reload).to be_canceled
        end
      end
    end
  end

  describe '.terminate_from_api' do
    let(:membership) { create(:membership) }
    let(:organization) { membership.organization }
    let(:customer) { create(:customer, organization: organization) }
    let(:subscription) { create(:subscription, customer: customer) }

    it 'terminates a subscription' do
      result = terminate_service.terminate_from_api(
        organization: organization,
        external_id: subscription.external_id,
      )

      aggregate_failures do
        expect(result.subscription).to be_present
        expect(result.subscription).to be_terminated
        expect(result.subscription.terminated_at).to be_present
      end
    end

    it 'enqueues a BillSubscriptionJob' do
      expect do
        terminate_service.terminate_from_api(
          organization: organization,
          external_id: subscription.external_id,
        )
      end.to have_enqueued_job(BillSubscriptionJob)
    end

    context 'when subscription is not found' do
      it 'returns an error' do
        result = terminate_service.terminate_from_api(
          organization: organization,
          external_id: subscription.external_id + '123',
        )

        expect(result.error.error_code).to eq('subscription_not_found')
      end
    end
  end

  describe '.terminate_and_start_next' do
    let(:subscription) { create(:subscription) }
    let(:next_subscription) { create(:subscription, previous_subscription_id: subscription.id, status: :pending) }
    let(:timestamp) { Time.zone.now.to_i }

    before { next_subscription }

    it 'terminates the subscription' do
      result = terminate_service.terminate_and_start_next(
        subscription: subscription,
        timestamp: timestamp,
      )

      aggregate_failures do
        expect(result).to be_success
        expect(subscription.reload).to be_terminated
      end
    end

    it 'starts the next subscription' do
      result = terminate_service.terminate_and_start_next(
        subscription: subscription,
        timestamp: timestamp,
      )

      aggregate_failures do
        expect(result).to be_success
        expect(result.subscription.id).to eq(next_subscription.id)
        expect(result.subscription).to be_active
      end
    end

    context 'when terminated subscription is payed in arrear' do
      before { subscription.plan.update!(pay_in_advance: false) }

      it 'enqueues a job to bill the existing subscription' do
        expect do
          terminate_service.terminate_and_start_next(
            subscription: subscription,
            timestamp: timestamp,
          )
        end.to have_enqueued_job(BillSubscriptionJob)
      end
    end

    context 'when next subscription is payed in advance' do
      let(:plan) { create(:plan, pay_in_advance: true) }
      let(:next_subscription) do
        create(
          :subscription,
          previous_subscription_id: subscription.id,
          plan: plan,
          status: :pending,
        )
      end

      before { subscription.plan.update!(pay_in_advance: true) }

      it 'enqueues a job to bill the existing subscription' do
        expect do
          terminate_service.terminate_and_start_next(
            subscription: subscription,
            timestamp: timestamp,
          )
        end.to have_enqueued_job(BillSubscriptionJob).twice
      end
    end
  end
end
