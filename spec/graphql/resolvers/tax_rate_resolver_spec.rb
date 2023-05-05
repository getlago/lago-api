# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Resolvers::TaxRateResolver, type: :graphql do
  let(:query) do
    <<~GQL
      query($taxRateId: ID!) {
        taxRate(id: $taxRateId) {
          id code description name value customersCount
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:tax_rate) { create(:tax_rate, organization:) }

  before do
    tax_rate
  end

  it 'returns a single tax rate' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      query:,
      variables: { taxRateId: tax_rate.id },
    )

    expect(result['data']['taxRate']).to include(
      'id' => tax_rate.id,
      'code' => tax_rate.code,
      'description' => tax_rate.description,
      'name' => tax_rate.name,
      'value' => tax_rate.value,
      'customersCount' => 0,
    )
  end

  context 'without current organization' do
    it 'returns an error' do
      result = execute_graphql(
        current_user: membership.user,
        query:,
        variables: { taxRateId: tax_rate.id },
      )

      expect_graphql_error(result:, message: 'Missing organization id')
    end
  end

  context 'when tax rate is not found' do
    it 'returns an error' do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        query:,
        variables: { taxRateId: 'unknown' },
      )

      expect_graphql_error(result:, message: 'Resource not found')
    end
  end
end
