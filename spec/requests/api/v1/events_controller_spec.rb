# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::EventsController, type: :request do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:metric) { create(:billable_metric, organization:) }
  let(:plan) { create(:plan, organization:) }
  let!(:subscription) { create(:subscription, customer:, organization:, plan:, started_at: 1.month.ago) }

  describe 'POST /api/v1/events' do
    subject do
      post_with_token(organization, '/api/v1/events', event: create_params)
    end

    let(:create_params) do
      {
        code: metric.code,
        transaction_id: SecureRandom.uuid,
        external_subscription_id: subscription.external_id,
        timestamp: Time.current.to_i,
        precise_total_amount_cents: '123.45',
        properties: {
          foo: 'bar'
        }
      }
    end

    include_examples 'requires API permission', 'event', 'write'

    it 'returns a success' do
      expect { subject }.to change(Event, :count).by(1)

      expect(response).to have_http_status(:success)
      expect(json[:event][:external_subscription_id]).to eq(subscription.external_id)
    end

    context 'with duplicated transaction_id' do
      let!(:event) { create(:event, organization:, external_subscription_id: subscription.external_id) }

      let(:create_params) do
        {
          code: metric.code,
          transaction_id: event.transaction_id,
          external_subscription_id: subscription.external_id,
          timestamp: Time.current.to_i,
          precise_total_amount_cents: '123.45',
          properties: {
            foo: 'bar'
          }
        }
      end

      it 'returns a not found response' do
        expect { subject }.not_to change(Event, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'when sending wrong format for the timestamp' do
      let(:create_params) do
        {
          code: metric.code,
          transaction_id: SecureRandom.uuid,
          external_subscription_id: subscription.external_id,
          timestamp: Time.current.to_s,
          precise_total_amount_cents: '123.45',
          properties: {
            foo: 'bar'
          }
        }
      end

      it 'returns a not found response' do
        expect { subject }.not_to change(Event, :count)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json[:error_details]).to eq({timestamp: ["invalid_format"]})
      end
    end
  end

  describe 'POST /api/v1/events/batch' do
    subject do
      post_with_token(organization, '/api/v1/events/batch', events: batch_params)
    end

    let(:batch_params) do
      [
        {
          code: metric.code,
          transaction_id: SecureRandom.uuid,
          external_subscription_id: subscription.external_id,
          timestamp: Time.current.to_i,
          precise_total_amount_cents: '123.45',
          properties: {
            foo: 'bar'
          }
        }
      ]
    end

    include_examples 'requires API permission', 'event', 'write'

    it 'returns a success' do
      expect { subject }.to change(Event, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(json[:events].first[:external_subscription_id]).to eq(subscription.external_id)
    end

    context 'with invalid timestamp for one event' do
      let(:batch_params) do
        [
          {
            code: metric.code,
            transaction_id: SecureRandom.uuid,
            external_subscription_id: subscription.external_id,
            timestamp: Time.current.to_i,
            precise_total_amount_cents: '123.45',
            properties: {
              foo: 'bar'
            }
          },
          {
            code: metric.code,
            transaction_id: SecureRandom.uuid,
            external_subscription_id: subscription.external_id,
            timestamp: Time.current.to_s,
            precise_total_amount_cents: '123.45',
            properties: {
              foo: 'bar'
            }
          }
        ]
      end

      it 'returns an error indicating which event contained which error' do
        expect { subject }.not_to change(Event, :count)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json[:error_details]).to eq({'1': {timestamp: ["invalid_format"]}})
      end
    end
  end

  describe 'GET /api/v1/events' do
    subject { get_with_token(organization, '/api/v1/events', params) }

    let!(:event) { create(:event, timestamp: 5.days.ago.to_date, organization:) }

    context 'without params' do
      let(:params) { {} }

      include_examples 'requires API permission', 'event', 'read'

      it 'returns events' do
        subject

        expect(response).to have_http_status(:ok)
        expect(json[:events].count).to eq(1)
        expect(json[:events].first[:lago_id]).to eq(event.id)
      end
    end

    context 'with pagination' do
      let(:params) { {page: 1, per_page: 1} }

      before { create(:event, organization:) }

      it 'returns events with correct meta data' do
        subject

        expect(response).to have_http_status(:ok)

        expect(json[:events].count).to eq(1)
        expect(json[:meta][:current_page]).to eq(1)
        expect(json[:meta][:next_page]).to eq(2)
        expect(json[:meta][:prev_page]).to eq(nil)
        expect(json[:meta][:total_pages]).to eq(2)
        expect(json[:meta][:total_count]).to eq(2)
      end
    end

    context 'with code' do
      let(:params) { {code: event.code} }

      before { create(:event, organization:) }

      it 'returns events' do
        subject

        expect(response).to have_http_status(:ok)
        expect(json[:events].count).to eq(1)
        expect(json[:events].first[:lago_id]).to eq(event.id)
      end
    end

    context 'with external subscription id' do
      let(:params) { {external_subscription_id: event.external_subscription_id} }

      before { create(:event, organization:) }

      it 'returns events' do
        subject

        expect(response).to have_http_status(:ok)
        expect(json[:events].count).to eq(1)
        expect(json[:events].first[:lago_id]).to eq(event.id)
      end
    end

    context 'with timestamp' do
      let(:params) do
        {timestamp_from: 2.days.ago.to_date, timestamp_to: Date.tomorrow.to_date}
      end

      let!(:matching_event) { create(:event, timestamp: 1.day.ago.to_date, organization:) }

      before { create(:event, timestamp: 3.days.ago.to_date, organization:) }

      it 'returns events with correct timestamp' do
        subject

        expect(response).to have_http_status(:ok)
        expect(json[:events].count).to eq(1)
        expect(json[:events].first[:lago_id]).to eq(matching_event.id)
      end
    end
  end

  describe 'GET /api/v1/events/:id' do
    subject { get_with_token(organization, "/api/v1/events/#{transaction_id}") }

    let(:event) { create(:event, organization_id: organization.id) }
    let(:transaction_id) { event.transaction_id }

    include_examples 'requires API permission', 'event', 'read'

    it 'returns an event' do
      subject

      expect(response).to have_http_status(:ok)

      %i[code transaction_id].each do |property|
        expect(json[:event][property]).to eq event.attributes[property.to_s]
      end

      expect(json[:event][:lago_subscription_id]).to eq event.subscription_id
      expect(json[:event][:lago_customer_id]).to eq event.customer_id
    end

    context 'with a non-existing transaction_id' do
      let(:transaction_id) { SecureRandom.uuid }

      it 'returns not found' do
        subject
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when event is deleted' do
      before { event.discard! }

      it 'returns not found' do
        subject
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'with clickhouse', clickhouse: true do
      let(:event) do
        Clickhouse::EventsRaw.create!(
          transaction_id: SecureRandom.uuid,
          organization_id: organization.id,
          external_subscription_id: subscription.external_id,
          code: metric.code,
          timestamp: 5.days.ago.to_date,
          properties: {}
        )
      end

      before { organization.update!(clickhouse_events_store: true) }

      it 'returns an event' do
        subject

        expect(response).to have_http_status(:ok)

        %i[code transaction_id].each do |property|
          expect(json[:event][property]).to eq event.attributes[property.to_s]
        end

        expect(json[:event][:lago_subscription_id]).to eq event.subscription_id
        expect(json[:event][:lago_customer_id]).to eq event.customer_id
      end
    end
  end

  describe 'POST /api/v1/events/estimate_fees' do
    subject do
      post_with_token(organization, '/api/v1/events/estimate_fees', event: event_params)
    end

    let(:charge) { create(:standard_charge, :pay_in_advance, plan:, billable_metric: metric) }
    let(:tax) { create(:tax, organization:) }

    let(:event_params) do
      {
        code: metric.code,
        external_subscription_id: subscription.external_id,
        transaction_id: SecureRandom.uuid,
        precise_total_amount_cents: '123.45',
        properties: {
          foo: 'bar'
        }
      }
    end

    before do
      charge
      tax
    end

    include_examples 'requires API permission', 'event', 'write'

    it 'returns a success' do
      subject

      aggregate_failures do
        expect(response).to have_http_status(:success)

        expect(json[:fees].count).to eq(1)

        fee = json[:fees].first
        expect(fee[:lago_id]).to be_nil
        expect(fee[:lago_group_id]).to be_nil
        expect(fee[:item][:type]).to eq('charge')
        expect(fee[:item][:code]).to eq(metric.code)
        expect(fee[:item][:name]).to eq(metric.name)
        expect(fee[:pay_in_advance]).to eq(true)
        expect(fee[:amount_cents]).to be_an(Integer)
        expect(fee[:amount_currency]).to eq('EUR')
        expect(fee[:units]).to eq('1.0')
        expect(fee[:events_count]).to eq(1)
      end
    end

    context 'with missing customer id' do
      let(:event_params) do
        {
          code: metric.code,
          external_subscription_id: nil,
          properties: {
            foo: 'bar'
          }
        }
      end

      it 'returns a not found error' do
        subject
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when metric code does not match an pay_in_advance charge' do
      let(:charge) { create(:standard_charge, plan:, billable_metric: metric) }

      let(:event_params) do
        {
          code: metric.code,
          external_subscription_id: subscription.external_id,
          properties: {
            foo: 'bar'
          }
        }
      end

      it 'returns a validation error' do
        subject
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end
end
