# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Resolvers::EventsResolver, type: :graphql, transaction: false do
  let(:query) do
    <<~GQL
      query {
        events(limit: 5) {
          collection {
            id
            code
            externalCustomerId
            transactionId
            timestamp
            receivedAt
            customerTimezone
            ipAddress
            apiClient
            payload
            billableMetricName
            matchBillableMetric
            matchCustomField
          }
          metadata { currentPage, totalCount }
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }

  let(:billable_metric) { create(:billable_metric, organization:) }

  let(:event) do
    create(
      :event,
      code: billable_metric.code,
      organization:,
      external_customer_id: customer.external_id,
      timestamp: 2.days.ago,
      properties: { foo_bar: 1234 },
      metadata: { user_agent: 'Lago Ruby v0.0.1', ip_address: '182.11.32.11' },
    )
  end

  before { event }

  it 'returns a list of events' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      query:,
    )

    events_response = result['data']['events']

    aggregate_failures do
      expect(events_response['collection'].count).to eq(Event.where(organization_id: organization.id).count)
      expect(events_response['collection'].first['id']).to eq(event.id)
      expect(events_response['collection'].first['code']).to eq(event.code)
      expect(events_response['collection'].first['externalCustomerId']).to eq(customer.external_id)
      expect(events_response['collection'].first['transactionId']).to eq(event.transaction_id)
      expect(events_response['collection'].first['timestamp']).to eq(event.timestamp.iso8601)
      expect(events_response['collection'].first['receivedAt']).to eq(event.created_at.iso8601)
      expect(events_response['collection'].first['customerTimezone']).to eq('TZ_UTC')
      expect(events_response['collection'].first['ipAddress']).to eq(event.metadata['ip_address'])
      expect(events_response['collection'].first['apiClient']).to eq(event.metadata['user_agent'])
      expect(events_response['collection'].first['payload']).to be_present
      expect(events_response['collection'].first['billableMetricName']).to eq(billable_metric.name)
      expect(events_response['collection'].first['matchBillableMetric']).to be_truthy
      expect(events_response['collection'].first['matchCustomField']).to be_truthy
    end
  end

  context 'with a deleted billable metric' do
    it 'does not return duplicated events' do
      billable_metric.discard!
      create(:billable_metric, organization:, code: billable_metric.code)

      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        query:,
      )

      events_response = result['data']['events']

      aggregate_failures do
        expect(events_response['collection'].count).to eq(Event.where(organization_id: organization.id).count)
        expect(events_response['collection'].first['id']).to eq(event.id)
      end
    end
  end

  context 'with missing billable_metric' do
    let(:event) do
      create(
        :event,
        code: 'foo',
        organization:,
        timestamp: 2.days.ago,
        properties: { foo_bar: 1234 },
      )
    end

    it 'returns a list of events' do
      event
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        query:,
      )

      events_response = result['data']['events']
      expect(events_response['collection'].first['matchBillableMetric']).to be_falsey
    end
  end

  context 'with missing custom field' do
    let(:billable_metric) { create(:billable_metric, organization:, field_name: 'mandatory') }

    it 'returns a list of events' do
      event
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        query:,
      )

      events_response = result['data']['events']
      expect(events_response['collection'].first['matchCustomField']).to be_falsey
    end
  end

  context 'with deleted customer' do
    before { customer.discard! }

    it 'returns the customer details' do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        query:,
      )

      events_response = result['data']['events']

      aggregate_failures do
        expect(events_response['collection'].first['externalCustomerId']).to eq(customer.external_id)
        expect(events_response['collection'].first['customerTimezone']).to eq('TZ_UTC')
      end
    end
  end
end
