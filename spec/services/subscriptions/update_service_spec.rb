# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Subscriptions::UpdateService, type: :service do
  subject(:update_service) { described_class.new(subscription:, params:) }

  let(:membership) { create(:membership) }
  let(:subscription) { create(:subscription, subscription_at: Time.current - 1.year) }

  describe '#call' do
    let(:subscription_at) { '2022-07-07T00:00:00Z' }
    let(:ending_at) { Time.current.beginning_of_day + 1.month }

    let(:params) do
      {
        name: 'new name',
        ending_at:,
        subscription_at:,
      }
    end

    before { subscription }

    it 'updates the subscription' do
      result = update_service.call

      expect(result).to be_success

      aggregate_failures do
        expect(result.subscription.name).to eq('new name')
        expect(result.subscription.ending_at).to eq(Time.current.beginning_of_day + 1.month)
        expect(result.subscription.subscription_at.to_s).not_to eq('2022-07-07')
      end
    end

    context 'when subscription_at is not passed at all' do
      let(:params) do
        {
          name: 'new name',
        }
      end

      it 'updates the subscription' do
        result = update_service.call

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
        result = update_service.call

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
          result = update_service.call

          expect(result).to be_success

          aggregate_failures do
            expect(result.subscription.name).to eq('new name')
            expect(result.subscription.status).to eq('active')
          end
        end

        it 'enqueues a job to bill the subscription' do
          expect do
            update_service.call
          end.to have_enqueued_job(BillSubscriptionJob)
        end
      end
    end

    context 'when subscription is nil' do
      let(:params) do
        {
          name: 'new name',
        }
      end

      let(:subscription) { nil }

      it 'returns an error' do
        result = update_service.call

        expect(result).not_to be_success
        expect(result.error.error_code).to eq('subscription_not_found')
      end
    end

    context 'when plan_overrides' do
      let(:plan) { create(:plan, organization: membership.organization) }
      let(:subscription) { create(:subscription, plan:, subscription_at: Time.current - 1.year) }
      let(:params) do
        {
          plan_overrides: {
            name: 'new name',
          },
        }
      end

      around { |test| lago_premium!(&test) }

      it 'creates the new plan accordingly' do
        update_service.call

        expect(subscription.plan.reload.name).to eq('new name')
        expect(subscription.plan_id).not_to eq(plan.id)
      end

      context 'with overriden plan' do
        let(:parent_plan) { create(:plan, organization: membership.organization) }
        let(:plan) { create(:plan, organization: membership.organization, parent_id: parent_plan.id) }

        it 'updates the plan accordingly' do
          update_service.call

          expect(subscription.plan.reload.name).to eq('new name')
          expect(subscription.plan_id).to eq(plan.id)
        end
      end
    end

    context 'when License is free and plan_overrides is passed' do
      let(:params) do
        {
          name: 'new name',
          plan_overrides: {
            amount_cents: 0,
          },
        }
      end

      it 'returns an error' do
        result = update_service.call

        expect(result).not_to be_success
        expect(result.error.code).to eq('feature_unavailable')
      end
    end
  end
end
