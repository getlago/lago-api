# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Resolvers::EventsResolver, type: :graphql do
  let(:query) do
    <<~GQL
      query {
        events(limit: 5) {
          collection {
            id,
            code,
            externalCustomerId,
            transactionId,
            timestamp,
            timestampInCustomerTimezone,
            receivedAt,
            receivedAtInCustomerTimezone,
            ipAddress,
            apiClient,
            payload,
            billableMetricName,
            matchBillableMetric,
            matchCustomField
          }
          metadata { currentPage, totalCount }
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  let(:billable_metric) { create(:billable_metric, organization: organization) }

  let(:event) do
    create(
      :event,
      code: billable_metric.code,
      organization: organization,
      timestamp: Time.zone.now - 2.days,
      properties: { foo_bar: 1234 },
      metadata: { user_agent: 'Lago Ruby v0.0.1', ip_address: '182.11.32.11' },
    )
  end

  before { event }

  it 'returns a list of events' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      query: query,
    )

    events_response = result['data']['events']

    aggregate_failures do
      expect(events_response['collection'].count).to eq(organization.events.count)
      expect(events_response['collection'].first['id']).to eq(event.id)
      expect(events_response['collection'].first['code']).to eq(event.code)
      expect(events_response['collection'].first['externalCustomerId']).to eq(event.customer.external_id)
      expect(events_response['collection'].first['transactionId']).to eq(event.transaction_id)
      expect(events_response['collection'].first['timestamp']).to eq(event.timestamp.iso8601)
      expect(events_response['collection'].first['receivedAt']).to eq(event.created_at.iso8601)
      expect(events_response['collection'].first['ipAddress']).to eq(event.metadata['ip_address'])
      expect(events_response['collection'].first['apiClient']).to eq(event.metadata['user_agent'])
      expect(events_response['collection'].first['payload']).to be_present
      expect(events_response['collection'].first['billableMetricName']).to eq(billable_metric.name)
      expect(events_response['collection'].first['matchBillableMetric']).to be_truthy
      expect(events_response['collection'].first['matchCustomField']).to be_truthy
    end
  end

  context 'with missing billable_metric' do
    let(:event) do
      create(
        :event,
        code: 'foo',
        organization: organization,
        timestamp: Time.zone.now - 2.days,
        properties: { foo_bar: 1234 },
      )
    end

    it 'returns a list of events' do
      event
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        query: query,
      )

      events_response = result['data']['events']
      expect(events_response['collection'].first['matchBillableMetric']).to be_falsey
    end
  end

  context 'with missing custom field' do
    let(:billable_metric) { create(:billable_metric, organization: organization, field_name: 'mandatory') }

    it 'returns a list of events' do
      event
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        query: query,
      )

      events_response = result['data']['events']
      expect(events_response['collection'].first['matchCustomField']).to be_falsey
    end
  end
end
