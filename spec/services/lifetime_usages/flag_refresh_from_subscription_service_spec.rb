# frozen_string_literal: true

require 'rails_helper'

RSpec.describe LifetimeUsages::FlagRefreshFromSubscriptionService, type: :service do
  subject(:flag_service) { described_class.new(subscription:) }

  let(:subscription) { create(:subscription, plan:, customer:) }
  let(:lifetime_usage) { create(:lifetime_usage, subscription:) }

  let(:customer) { create(:customer) }
  let(:plan) { create(:plan, organization: customer.organization) }

  let(:threshold) { create(:usage_threshold, plan: plan) }

  before { threshold }

  describe '.call' do
    it 'flags the lifetime usage for refresh' do
      expect { flag_service.call }
        .to change { lifetime_usage.reload.recalculate_current_usage }.from(false).to(true)
    end

    context 'when the subscription is not active' do
      let(:subscription) { create(:subscription, :terminated) }

      it 'does not flags the lifetime usage', aggregate_failure: true do
        expect(flag_service.call).to be_success
        expect(lifetime_usage.reload.recalculate_current_usage).to be(false)
      end
    end

    context 'when the lifetime usage does not exists' do
      let(:lifetime_usage) { nil }

      it 'creates a new lifetime usage', aggregate_failures: true do
        expect { flag_service.call }
          .to change(LifetimeUsage, :count).by(1)

        expect(subscription.lifetime_usage.recalculate_current_usage).to be(true)
      end
    end

    context 'when the subscription plan does not have usage thresholds' do
      let(:threshold) { nil }

      it 'does not flags the lifetime usage', aggregate_failures: true do
        expect(flag_service.call).to be_success
        expect(lifetime_usage.reload.recalculate_current_usage).to be(false)
      end
    end
  end
end
