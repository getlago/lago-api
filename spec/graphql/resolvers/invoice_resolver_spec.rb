# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Resolvers::InvoiceResolver, type: :graphql do
  let(:query) do
    <<~GQL
      query($id: ID!) {
        invoice(id: $id) {
          id
          number
          customer {
            id
            name
          }
          invoiceSubscriptions {
            subscription {
              id
            }
            fees {
              id
              group { id key value }
            }
          }
          subscriptions {
            id
          }
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization: organization) }
  let(:invoice_subscription) { create(:invoice_subscription, invoice: create(:invoice, customer: customer)) }
  let(:invoice) { invoice_subscription.invoice }
  let(:subscription) { invoice_subscription.subscription }
  let(:fee) { create(:fee, subscription: subscription, invoice: invoice, amount_cents: 10) }

  before { fee }

  it 'returns a single invoice' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      query: query,
      variables: {
        id: invoice.id,
      },
    )

    data = result['data']['invoice']

    expect(data['id']).to eq(invoice.id)
    expect(data['number']).to eq(invoice.number)
    expect(data['customer']['id']).to eq(customer.id)
    expect(data['customer']['name']).to eq(customer.name)
    expect(data['invoiceSubscriptions'][0]['subscription']['id']).to eq(subscription.id)
    expect(data['invoiceSubscriptions'][0]['fees'][0]['id']).to eq(fee.id)
  end

  it 'includes group for each fee' do
    group1 = create(:group, key: 'cloud', value: 'aws')
    group2 = create(:group, key: 'region', value: 'usa', parent_group_id: group1.id)
    fee.update!(group_id: group2.id)

    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      query: query,
      variables: { id: invoice.id },
    )

    group = result['data']['invoice']['invoiceSubscriptions'][0]['fees'][0]['group']

    expect(group['id']).to eq(group2.id)
    expect(group['key']).to eq('aws')
    expect(group['value']).to eq('usa')
  end

  context 'when invoice is not found' do
    it 'returns an error' do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: invoice.organization,
        query: query,
        variables: {
          id: 'foo',
        },
      )

      expect_graphql_error(
        result: result,
        message: 'Resource not found',
      )
    end
  end
end
