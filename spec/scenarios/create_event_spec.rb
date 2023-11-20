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
    it 'returns the created event' do
      result = create_event params

      expect(result['event']).to be_present
      expect(result['event']['code']).to eq(billable_metric.code)

      perform_all_enqueued_jobs

      event = organization.events.order(created_at: :asc).last
      expect(event).to have_attributes(
        code: billable_metric.code,
        customer_id: nil,
        external_customer_id: nil,
        subscription_id: nil,
        external_subscription_id: nil,
      )
    end
  end

  context 'with unknown external_customer_id' do
    it 'returns the created event' do
      result = create_event(params.merge(external_customer_id: 'unknown'))

      expect(result['event']).to be_present
      expect(result['event']['code']).to eq(billable_metric.code)
      expect(result['event']['external_customer_id']).to eq('unknown')

      perform_all_enqueued_jobs

      event = organization.events.order(created_at: :asc).last
      expect(event).to have_attributes(
        code: billable_metric.code,
        customer_id: nil,
        external_customer_id: 'unknown',
        subscription_id: nil,
        external_subscription_id: nil,
      )
    end
  end

  context 'with external_customer_id from another organization' do
    let(:organization2) { create(:organization, webhook_url: nil) }
    let(:customer2) { create(:customer, organization: organization2) }

    it 'returns the created event' do
      result = create_event(params.merge(external_customer_id: customer2.external_id))

      expect(result['event']).to be_present
      expect(result['event']['code']).to eq(billable_metric.code)
      expect(result['event']['external_customer_id']).to eq(customer2.external_id)

      perform_all_enqueued_jobs

      event = organization.events.order(created_at: :asc).last
      expect(event).to have_attributes(
        code: billable_metric.code,
        customer_id: nil,
        external_customer_id: customer2.external_id,
        subscription_id: nil,
        external_subscription_id: nil,
      )
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

      perform_all_enqueued_jobs

      event = organization.events.order(created_at: :asc).last
      expect(event).to have_attributes(
        code: billable_metric.code,
        external_customer_id: 'unknown',
        external_subscription_id: subscription.external_id,
      )
    end
  end

  context 'with unknown external_customer_id and unknown external_subscription_id' do
    it 'returns the created event' do
      result = create_event(params.merge(external_customer_id: 'unknown', external_subscription_id: 'unknown'))

      expect(result['event']).to be_present
      expect(result['event']['code']).to eq(billable_metric.code)
      expect(result['event']['external_customer_id']).to eq('unknown')
      expect(result['event']['external_subscription_id']).to eq('unknown')

      perform_all_enqueued_jobs

      event = organization.events.order(created_at: :asc).last
      expect(event).to have_attributes(
        code: billable_metric.code,
        external_customer_id: 'unknown',
        external_subscription_id: 'unknown',
      )
    end
  end

  context 'with external_subscription_id from another organization' do
    let(:organization2) { create(:organization, webhook_url: nil) }
    let(:customer2) { create(:customer, organization: organization2) }
    let(:subscription2) { create(:active_subscription, customer: customer2) }

    it 'returns the created event' do
      result = create_event(params.merge(external_subscription_id: subscription2.external_id))

      expect(result['event']).to be_present
      expect(result['event']['code']).to eq(billable_metric.code)
      expect(result['event']['external_subscription_id']).to eq(subscription2.external_id)

      perform_all_enqueued_jobs

      event = organization.events.order(created_at: :asc).last
      expect(event).to have_attributes(
        code: billable_metric.code,
        external_customer_id: nil,
        external_subscription_id: subscription2.external_id,
      )
    end
  end

  context 'with valid external_subscription_id' do
    it 'creates the event successfully' do
      expect do
        create_event(params.merge(external_subscription_id: subscription.external_id))
      end.to change(Event, :count)

      perform_all_enqueued_jobs

      event = organization.events.order(created_at: :asc).last
      expect(event).to have_attributes(
        code: billable_metric.code,
        external_customer_id: subscription.customer.external_id,
        external_subscription_id: subscription.external_id,
      )
    end
  end

  context 'with not yet started subscription' do
    let(:subscription) { create(:active_subscription, customer:, started_at: 1.day.from_now) }

    it 'returns the created event' do
      result = create_event(params.merge(external_subscription_id: subscription.external_id))

      expect(result['event']).to be_present
      expect(result['event']['external_subscription_id']).to eq(subscription.external_id)

      perform_all_enqueued_jobs

      event = organization.events.order(created_at: :asc).last
      expect(event).to have_attributes(
        code: billable_metric.code,
        external_customer_id: subscription.customer.external_id,
        external_subscription_id: subscription.external_id,
      )
    end
  end

  context 'with subscription started in the same second' do
    let(:subscription) { create(:active_subscription, customer:, started_at: Time.current) }

    it 'returns the created event' do
      expect do
        create_event(params.merge(external_subscription_id: subscription.external_id))
      end.to change(Event, :count)

      perform_all_enqueued_jobs

      event = organization.events.order(created_at: :asc).last
      expect(event).to have_attributes(
        code: billable_metric.code,
        external_customer_id: subscription.customer.external_id,
        external_subscription_id: subscription.external_id,
      )
    end
  end

  context 'with terminated subscription' do
    let(:subscription) { create(:subscription, :terminated, customer:, terminated_at: 1.hour.ago) }

    it 'returns the created event' do
      result = create_event(params.merge(external_subscription_id: subscription.external_id))

      expect(result['event']).to be_present
      expect(result['event']['external_subscription_id']).to eq(subscription.external_id)

      perform_all_enqueued_jobs

      event = organization.events.order(created_at: :asc).last
      expect(event).to have_attributes(
        code: billable_metric.code,
        external_customer_id: subscription.customer.external_id,
        external_subscription_id: subscription.external_id,
      )
    end
  end

  context 'with subscription terminated in the same second' do
    let(:subscription) { create(:subscription, :terminated, customer:, terminated_at: Time.current) }

    it 'creates the event successfully' do
      expect do
        create_event(params.merge(external_subscription_id: subscription.external_id))
      end.to change(Event, :count)

      perform_all_enqueued_jobs

      event = organization.events.order(created_at: :asc).last
      expect(event).to have_attributes(
        code: billable_metric.code,
        external_customer_id: subscription.customer.external_id,
        external_subscription_id: subscription.external_id,
      )
    end
  end

  context 'with terminated subscription but timestamp when active' do
    let(:subscription) { create(:subscription, :terminated, customer:, terminated_at: 24.hours.ago) }

    it 'creates the event successfully' do
      expect do
        create_event(
          params.merge(
            external_subscription_id: subscription.external_id,
            timestamp: 24.hours.ago.to_i,
          ),
        )
      end.to change(Event, :count)

      perform_all_enqueued_jobs

      event = organization.events.order(created_at: :asc).last
      expect(event).to have_attributes(
        code: billable_metric.code,
        external_customer_id: subscription.customer.external_id,
        external_subscription_id: subscription.external_id,
      )
    end
  end

  context 'with external_customer_id but multiple subscriptions' do
    let(:subscription2) { create(:active_subscription, customer:, started_at: subscription.started_at - 1.day) }

    before { subscription2 }

    it 'returns the created event' do
      result = create_event(params.merge(external_customer_id: customer.external_id))

      expect(result['event']).to be_present
      expect(result['event']['external_customer_id']).to eq(customer.external_id)

      perform_all_enqueued_jobs

      event = organization.events.order(created_at: :asc).last
      expect(event).to have_attributes(
        code: billable_metric.code,
        external_customer_id: customer.external_id,
        external_subscription_id: nil,
      )
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
      end.to change { Event.where(external_subscription_id: subscription2.external_id).count }
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

    it 'creates the event' do
      expect do
        create_event(params.merge(external_subscription_id: subscription.external_id))
      end.to change { Event.where(external_subscription_id: subscription.external_id).count }
    end
  end
end
