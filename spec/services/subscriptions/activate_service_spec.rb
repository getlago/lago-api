# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Subscriptions::ActivateService, type: :service do
  subject(:activate_service) { described_class.new(timestamp: Time.current.to_i) }

  describe 'activate_all_expired' do
    let(:active_subscription) { create(:active_subscription) }
    let(:pending_subscriptions) { create_list(:pending_subscription, 3, subscription_date: Time.current.to_date) }

    let(:future_pending_subscriptions) do
      create_list(:pending_subscription, 2, subscription_date: (Time.current + 10.days).to_date)
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
  end
end
