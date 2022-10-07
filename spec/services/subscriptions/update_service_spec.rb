# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Subscriptions::UpdateService, type: :service do
  subject(:update_service) { described_class.new(membership.user) }

  let(:membership) { create(:membership) }
  let(:subscription) { create(:subscription) }

  describe 'update' do
    let(:subscription_date) { '2022-07-07' }

    before { subscription }

    let(:update_args) do
      {
        id: subscription.id,
        name: 'new name',
        subscription_date: subscription_date,
      }
    end

    it 'updates the subscription' do
      result = update_service.update(**update_args)

      expect(result).to be_success

      aggregate_failures do
        expect(result.subscription.name).to eq('new name')
        expect(result.subscription.subscription_date.to_s).not_to eq('2022-07-07')
      end
    end

    context 'when subscription_date is not passed at all' do
      let(:update_args) do
        {
          id: subscription.id,
          name: 'new name',
        }
      end

      it 'updates the subscription' do
        result = update_service.update(**update_args)

        expect(result).to be_success

        aggregate_failures do
          expect(result.subscription.name).to eq('new name')
          expect(result.subscription.subscription_date.to_s).not_to eq('2022-07-07')
        end
      end
    end

    context 'when subscription is starting in the future' do
      let(:subscription) { create(:pending_subscription) }

      it 'updates the subscription_date as well' do
        result = update_service.update(**update_args)

        expect(result).to be_success

        aggregate_failures do
          expect(result.subscription.name).to eq('new name')
          expect(result.subscription.subscription_date.to_s).to eq('2022-07-07')
        end
      end

      context 'when subscription date is set to today' do
        let(:subscription_date) { Time.current.to_date }

        before { subscription.plan.update!(pay_in_advance: true) }

        it 'activates subscription' do
          result = update_service.update(**update_args)

          expect(result).to be_success

          aggregate_failures do
            expect(result.subscription.name).to eq('new name')
            expect(result.subscription.status).to eq('active')
          end
        end

        it 'enqueues a job to bill the subscription' do
          expect do
            update_service.update(**update_args)
          end.to have_enqueued_job(BillSubscriptionJob)
        end
      end
    end

    context 'with invalid id' do
      let(:update_args) do
        {
          id: subscription.id + '123',
          name: 'new name',
        }
      end

      it 'returns an error' do
        result = update_service.update(**update_args)

        expect(result).not_to be_success
        expect(result.error.error_code).to eq('subscription_not_found')
      end
    end
  end

  describe 'update_from_api' do
    let(:organization) { membership.organization }
    let(:update_args) do
      {
        name: 'new name',
        subscription_date: '2022-07-07',
      }
    end
    let(:customer) { create(:customer, organization: organization) }
    let(:subscription) { create(:subscription, customer: customer) }

    before { subscription }

    it 'updates the subscription' do
      result = update_service.update_from_api(
        organization: organization,
        external_id: subscription.external_id,
        params: update_args,
      )

      expect(result).to be_success

      aggregate_failures do
        expect(result.subscription.name).to eq('new name')
        expect(result.subscription.subscription_date.to_s).not_to eq('2022-07-07')
      end
    end

    context 'when subscription is starting in the future' do
      let(:subscription) { create(:pending_subscription, customer: customer) }

      it 'updates the subscription_date as well' do
        result = update_service.update_from_api(
          organization: organization,
          external_id: subscription.external_id,
          params: update_args,
        )

        expect(result).to be_success

        aggregate_failures do
          expect(result.subscription.name).to eq('new name')
          expect(result.subscription.subscription_date.to_s).to eq('2022-07-07')
        end
      end
    end

    context 'with invalid external_id' do
      it 'returns an error' do
        result = update_service.update_from_api(
          organization: organization,
          external_id: subscription.external_id + '123',
          params: update_args,
        )

        expect(result).not_to be_success
        expect(result.error.error_code).to eq('subscription_not_found')
      end
    end
  end
end
