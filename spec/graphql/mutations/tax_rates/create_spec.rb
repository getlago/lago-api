# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::TaxRates::Create, type: :graphql do
  let(:membership) { create(:membership) }
  let(:input) do
    {
      name: 'Tax rate name',
      code: 'tax-rate-code',
      description: 'Tax rate description',
      value: 15.0,
    }
  end

  let(:mutation) do
    <<-GQL
      mutation($input: TaxRateCreateInput!) {
        createTaxRate(input: $input) {
          id name code description value
        }
      }
    GQL
  end

  it 'creates a tax rate' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: membership.organization,
      query: mutation,
      variables: { input: },
    )

    expect(result['data']['createTaxRate']).to include(
      'id' => String,
      'name' => 'Tax rate name',
      'code' => 'tax-rate-code',
      'description' => 'Tax rate description',
      'value' => 15.0,
    )
  end

  context 'without current user' do
    it 'returns an error' do
      result = execute_graphql(
        current_organization: membership.organization,
        query: mutation,
        variables: { input: },
      )

      expect_unauthorized_error(result)
    end
  end

  context 'without current organization' do
    it 'returns an error' do
      result = execute_graphql(
        current_user: membership.user,
        query: mutation,
        variables: { input: },
      )

      expect_forbidden_error(result)
    end
  end
end
