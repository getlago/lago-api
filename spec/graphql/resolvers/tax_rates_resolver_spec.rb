# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Resolvers::TaxRatesResolver, type: :graphql do
  let(:query) do
    <<~GQL
      query {
        taxRates(limit: 5) {
          collection { id name }
          metadata { currentPage, totalCount }
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:tax_rate) { create(:tax_rate, organization:) }

  before { tax_rate }

  it 'returns a list of tax rates' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      query:,
    )

    tax_rates_response = result['data']['taxRates']

    aggregate_failures do
      expect(tax_rates_response['collection'].first).to include(
        'id' => tax_rate.id,
        'name' => tax_rate.name,
      )

      expect(tax_rates_response['metadata']).to include(
        'currentPage' => 1,
        'totalCount' => 1,
      )
    end
  end

  context 'without current organization' do
    it 'returns an error' do
      result = execute_graphql(current_user: membership.user, query:)

      expect_graphql_error(result:, message: 'Missing organization id')
    end
  end

  context 'when not member of the organization' do
    it 'returns an error' do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: create(:organization),
        query:,
      )

      expect_graphql_error(result:, message: 'Not in organization')
    end
  end
end
