# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Resolvers::CustomersResolver, type: :graphql do
  let(:required_permission) { 'customers:view' }
  let(:query) do
    <<~GQL
      query {
        customers(limit: 5) {
          collection { id externalId name }
          metadata { currentPage, totalCount }
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  it_behaves_like 'requires current user'
  it_behaves_like 'requires current organization'
  it_behaves_like 'requires permission', 'customers:view'

  it 'returns a list of customers' do
    customer = create(:customer, organization:)

    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:
    )

    customers_response = result['data']['customers']

    aggregate_failures do
      expect(customers_response['collection'].count).to eq(organization.customers.count)
      expect(customers_response['collection'].first['id']).to eq(customer.id)

      expect(customers_response['metadata']['currentPage']).to eq(1)
      expect(customers_response['metadata']['totalCount']).to eq(1)
    end
  end

  context 'without current organization' do
    it 'returns an error' do
      result = execute_graphql(current_user: membership.user, query:)

      expect_graphql_error(
        result:,
        message: 'Missing organization id'
      )
    end
  end
end
