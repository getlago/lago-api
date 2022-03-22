# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Resolvers::ProductsResolver, type: :graphql do
  let(:query) do
    <<~GQL
      query {
        products(limit: 5) {
          collection { id }
          metadata { currentPage, totalCount }
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  it 'returs a list of products' do
    product = create(:product, organization: organization)

    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      query: query
    )

    products_response = result['data']['products']

    aggregate_failures do
      expect(products_response['collection'].count).to eq(organization.products.count)
      expect(products_response['collection']).to eq([{ 'id' => product.id }])

      expect(products_response['metadata']['currentPage']).to eq(1)
      expect(products_response['metadata']['totalCount']).to eq(1)
    end
  end

  context 'without current organization' do
    it 'returns an error' do
      result = execute_graphql(current_user: membership.user, query: query)

      expect_graphql_error(
        result: result,
        message: 'Missing organization id'
      )
    end
  end

  context 'when not member of the organization' do
    it 'returns an error' do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: create(:organization),
        query: query
      )

      expect_graphql_error(
        result: result,
        message: 'Not in organization'
      )
    end
  end
end
