# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Subscriptions::ActivateService, type: :service do
  subject(:activate_service) { described_class.new(timestamp: timestamp.to_i) }

  let(:timestamp) { Time.current }

  describe 'activate_all_expired' do
    let(:active_subscription) { create(:active_subscription) }
    let(:pending_subscriptions) { create_list(:pending_subscription, 3, subscription_at: timestamp) }

    let(:future_pending_subscriptions) do
      create_list(:pending_subscription, 2, subscription_at: (timestamp + 10.days))
    end

    before do
      active_subscription
      pending_subscriptions
      future_pending_subscriptions
    end

    it 'activates all pending subscriptions with subscription date set to today' do
      expect { activate_service.activate_all_pending }
        .to change(Subscription.pending, :count).by(-3)
        .and change(Subscription.active, :count).by(3)
    end

    context 'with customer timezone' do
      let(:timestamp) { DateTime.parse('2022-10-21 00:30:00') }
      let(:pending_subscription) { pending_subscriptions.first }

      before do
        active_subscription
        future_pending_subscriptions

        pending_subscription.customer.update!(timezone: 'America/New_York')
        pending_subscription.update!(subscription_at: DateTime.parse('2022-10-21'))
      end

      it 'takes timezone into account' do
        expect { activate_service.activate_all_pending }
          .to change(Subscription.pending, :count).by(-2)
          .and change(Subscription.active, :count).by(2)
      end
    end
  end
end
