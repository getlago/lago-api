# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Resolvers::AddOnResolver, type: :graphql do
  let(:query) do
    <<~GQL
      query($addOnId: ID!) {
        addOn(id: $addOnId) {
          id, name, customerCount
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:add_on) { create(:add_on, organization: organization) }
  let(:customer) { create(:customer, organization: organization) }
  let(:customer2) { create(:customer, organization: organization) }
  let(:applied_add_on_list) { create_list(:applied_add_on, 3, add_on: add_on, customer: customer) }
  let(:applied_add_on) { create(:applied_add_on, add_on: add_on, customer: customer2) }

  before do
    customer
    customer2
    applied_add_on_list
    applied_add_on

    3.times do
      create(:subscription, customer: customer)
    end
  end

  it 'returns a single add-on' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      query: query,
      variables: {
        addOnId: add_on.id,
      },
    )

    add_on_response = result['data']['addOn']

    aggregate_failures do
      expect(add_on_response['id']).to eq(add_on.id)
      expect(add_on_response['name']).to eq(add_on.name)
      expect(add_on_response['customerCount']).to eq(2)
    end
  end

  context 'without current organization' do
    it 'returns an error' do
      result = execute_graphql(
        current_user: membership.user,
        query: query,
        variables: {
          addOnId: add_on.id,
        },
      )

      expect_graphql_error(
        result: result,
        message: 'Missing organization id',
        )
    end
  end

  context 'when add-on is not found' do
    it 'returns an error' do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        query: query,
        variables: {
          addOnId: 'invalid',
        },
      )

      expect_graphql_error(
        result: result,
        message: 'Resource not found',
      )
    end
  end
end
