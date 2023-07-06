# frozen_string_literal: true

require 'rails_helper'

describe 'Create Event Scenarios', :scenarios, type: :request do
  let(:organization) { create(:organization, webhook_url: nil) }
  let(:customer) { create(:customer, organization:) }
  let(:billable_metric) { create(:billable_metric, organization:) }
  let(:subscription) { create(:active_subscription, customer:) }
  let(:params) do
    { code: billable_metric.code, transaction_id: SecureRandom.uuid }
  end

  before { subscription }

  context 'without external_customer_id and external_subscription_id' do
    it 'returns a subscription not found error' do
      result = create_event params
      expect(result['code']).to eq('subscription_not_found')
    end
  end

  context 'with unknown external_customer_id' do
    it 'returns a customer not found error' do
      result = create_event(params.merge(external_customer_id: 'unknown'))
      expect(result['code']).to eq('customer_not_found')
    end
  end

  context 'with external_customer_id from another organization' do
    let(:organization2) { create(:organization, webhook_url: nil) }
    let(:customer2) { create(:customer, organization: organization2) }

    it 'returns a customer not found error' do
      result = create_event(params.merge(external_customer_id: customer2.external_id))
      expect(result['code']).to eq('customer_not_found')
    end
  end

  context 'with unknown external_customer_id but valid external_subscription_id' do
    it 'creates the event successfully' do
      expect do
        create_event(
          params.merge(
            external_customer_id: 'unknown',
            external_subscription_id: subscription.external_id,
          ),
        )
      end.to change(Event, :count)
    end
  end

  context 'with unknown external_customer_id and unknown external_subscription_id' do
    it 'returns a customer not found error' do
      result = create_event(params.merge(external_customer_id: 'unknown', external_subscription_id: 'unknown'))
      expect(result['code']).to eq('customer_not_found')
    end
  end

  context 'with external_subscription_id from another organization' do
    let(:organization2) { create(:organization, webhook_url: nil) }
    let(:customer2) { create(:customer, organization: organization2) }
    let(:subscription2) { create(:active_subscription, customer: customer2) }

    it 'returns a subscription not found error' do
      result = create_event(params.merge(external_subscription_id: subscription2.external_id))
      expect(result['code']).to eq('subscription_not_found')
    end
  end

  context 'with valid external_subscription_id' do
    it 'creates the event successfully' do
      expect do
        create_event(params.merge(external_subscription_id: subscription.external_id))
      end.to change(Event, :count)
    end
  end

  context 'with not yet started subscription' do
    let(:subscription) { create(:active_subscription, customer:, started_at: 1.day.from_now) }

    it 'returns a subscription not found error' do
      result = create_event params
      expect(result['code']).to eq('subscription_not_found')
    end
  end

  context 'with terminated subscription' do
    let(:subscription) { create(:terminated_subscription, customer:) }

    it 'returns a subscription not found error' do
      result = create_event params
      expect(result['code']).to eq('subscription_not_found')
    end
  end

  context 'with terminated subscription but timestamp when active' do
    let(:subscription) { create(:terminated_subscription, customer:, terminated_at: 24.hours.ago) }

    it 'creates the event successfully' do
      expect do
        create_event(
          params.merge(
            external_subscription_id: subscription.external_id,
            timestamp: 24.hours.ago.to_i,
          ),
        )
      end.to change(Event, :count)
    end
  end

  context 'with external_customer_id but multiple subscriptions' do
    let(:subscription2) { create(:active_subscription, customer:, started_at: subscription.started_at - 1.day) }

    before { subscription2 }

    it 'returns a subscription not found error' do
      result = create_event(params.merge(external_customer_id: customer.external_id))
      expect(result['code']).to eq('subscription_not_found')
    end
  end

  context 'with external_customer_id and external_subscription_id and multiple subscriptions' do
    let(:subscription2) { create(:active_subscription, customer:, started_at: subscription.started_at - 1.day) }

    before { subscription2 }

    it 'creates the event on the corresponding subscription' do
      expect do
        create_event(
          params.merge(
            external_customer_id: customer.external_id,
            external_subscription_id: subscription2.external_id,
          ),
        )
      end.to change { subscription2.events.reload.count }

      expect(subscription.events.count).to eq(0)
    end
  end

  context 'with external_subscription_id but multiple subscriptions' do
    let(:subscription2) do
      create(
        :pending_subscription,
        customer:,
        external_id: subscription.external_id,
      )
    end

    before { subscription2 }

    it 'creates the event on the active subscription' do
      expect do
        create_event(params.merge(external_subscription_id: subscription.external_id))
      end.to change { subscription.events.reload.count }

      expect(subscription2.events.count).to eq(0)
    end
  end
end
