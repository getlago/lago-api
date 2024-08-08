# frozen_string_literal: true

require 'rails_helper'

RSpec.describe LifetimeUsages::FlagForSubscriptionService, type: :service do
  subject(:flag_service) { described_class.new(subscription:, invoiced_usage:, current_usage:) }

  let(:subscription) { create(:subscription) }
  let(:invoiced_usage) { true }
  let(:current_usage) { true }

  # let(:usage_thresholds) do
  #   create_list(:usage_threshold, 2, plan: subscription.plan)
  # end

  describe '.call' do
    context 'when license is not premium' do
      it 'does not flag a lifetime usage for refresh' do
        result = flag_service.call

        expect(result).to be_success
        expect(result.lifetime_usage).to be_nil
      end
    end

    context 'when license is premium' do
      around { |test| lago_premium!(&test) }

      it 'flags a lifetime usage for refresh', aggregate_failures: true do
        result = flag_service.call

        expect(result).to be_success
        expect(result.lifetime_usage).to be_present

        lifetime_usage = result.lifetime_usage
        expect(lifetime_usage.organization_id).to eq(subscription.organization.id)
        expect(lifetime_usage.external_subscription_id).to eq(subscription.external_id)
        expect(lifetime_usage.currency).to eq(subscription.plan.amount_currency)
        expect(lifetime_usage.recalculate_invoiced_usage).to be_truthy
        expect(lifetime_usage.recalculate_current_usage).to be_truthy
      end

      context 'when invoice usage is not flagged' do
        let(:invoiced_usage) { false }

        it 'does not flag the lifetime usage', aggregate_failures: true do
          result = flag_service.call

          expect(result).to be_success

          lifetime_usage = result.lifetime_usage
          expect(lifetime_usage.recalculate_invoiced_usage).to be_falsey
        end
      end

      context 'when invoice usage is not flagged' do
        let(:current_usage) { false }

        it 'does not flag the lifetime usage', aggregate_failures: true do
          result = flag_service.call

          expect(result).to be_success

          lifetime_usage = result.lifetime_usage
          expect(lifetime_usage.recalculate_current_usage).to be_falsey
        end
      end

      context 'when lifetime usage already exists' do
        let(:lifetime_usage) { create(:lifetime_usage, subscription:) }

        before { lifetime_usage }

        it 'updates the lifetime usage', aggregate_failures: true do
          result = flag_service.call

          expect(result).to be_success
          expect(result.lifetime_usage).to eq(lifetime_usage)
          expect(result.lifetime_usage.recalculate_invoiced_usage).to be_truthy
          expect(result.lifetime_usage.recalculate_current_usage).to be_truthy
        end
      end

      context 'when subscription is not found' do
        let(:subscription) { nil }

        it 'returns a not found failure', aggregate_failures: true do
          result = flag_service.call

          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::NotFoundFailure)
          expect(result.error.error_code).to eq('subscription_not_found')
        end
      end

      # context 'when plan does not have usage thresholds' do
      #   let(:usage_thresholds) { [] }

      #   it 'does not flag the lifetime usage for refresh' do
      #     result = flag_service.call

      #     expect(result).not_to be_success
      #     expect(result.lifetime_usage).to be_nil
      #   end
      # end
    end
  end
end
