# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Subscriptions::UpdateService, type: :service do
  subject(:update_service) { described_class.new(membership.user) }

  let(:membership) { create(:membership) }
  let(:subscription) { create(:subscription) }

  describe 'update' do
    let(:subscription_at) { '2022-07-07T00:00:00Z' }

    let(:update_args) do
      {
        name: 'new name',
        subscription_at:,
      }
    end

    before { subscription }

    it 'updates the subscription' do
      result = update_service.update(subscription:, args: update_args)

      expect(result).to be_success

      aggregate_failures do
        expect(result.subscription.name).to eq('new name')
        expect(result.subscription.subscription_at.to_s).not_to eq('2022-07-07')
      end
    end

    context 'when subscription_at is not passed at all' do
      let(:update_args) do
        {
          name: 'new name',
        }
      end

      it 'updates the subscription' do
        result = update_service.update(subscription:, args: update_args)

        expect(result).to be_success

        aggregate_failures do
          expect(result.subscription.name).to eq('new name')
          expect(result.subscription.subscription_at.to_s).not_to eq('2022-07-07')
        end
      end
    end

    context 'when subscription is starting in the future' do
      let(:subscription) { create(:pending_subscription) }

      it 'updates the subscription_at as well' do
        result = update_service.update(subscription:, args: update_args)

        expect(result).to be_success

        aggregate_failures do
          expect(result.subscription.name).to eq('new name')
          expect(result.subscription.subscription_at.to_s).to eq('2022-07-07 00:00:00 UTC')
        end
      end

      context 'when subscription date is set to today' do
        let(:subscription_at) { Time.current }

        before { subscription.plan.update!(pay_in_advance: true) }

        it 'activates subscription' do
          result = update_service.update(subscription:, args: update_args)

          expect(result).to be_success

          aggregate_failures do
            expect(result.subscription.name).to eq('new name')
            expect(result.subscription.status).to eq('active')
          end
        end

        it 'enqueues a job to bill the subscription' do
          expect do
            update_service.update(subscription:, args: update_args)
          end.to have_enqueued_job(BillSubscriptionJob)
        end
      end
    end

    context 'when subscription is nil' do
      let(:update_args) do
        {
          name: 'new name',
        }
      end

      it 'returns an error' do
        result = update_service.update(subscription: nil, args: update_args)

        expect(result).not_to be_success
        expect(result.error.error_code).to eq('subscription_not_found')
      end
    end
  end
end
