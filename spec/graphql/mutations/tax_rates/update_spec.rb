# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::TaxRates::Update, type: :graphql do
  let(:membership) { create(:membership) }
  let(:tax_rate) { create(:tax_rate, organization: membership.organization) }
  let(:input) do
    {
      id: tax_rate.id,
      name: 'Updated tax rate name',
      code: 'updated-tax-rate-code',
      description: 'Updated tax rate description',
      value: 30.0,
    }
  end

  let(:mutation) do
    <<-GQL
      mutation($input: TaxRateUpdateInput!) {
        updateTaxRate(input: $input) {
          id name code description value
        }
      }
    GQL
  end

  it 'updates a tax rate' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: membership.organization,
      query: mutation,
      variables: { input: },
    )

    expect(result['data']['updateTaxRate']).to include(
      'id' => String,
      'name' => 'Updated tax rate name',
      'code' => 'updated-tax-rate-code',
      'description' => 'Updated tax rate description',
      'value' => 30.0,
    )
  end

  context 'without current_organization' do
    it 'returns an error' do
      result = execute_graphql(
        current_user: membership.user,
        query: mutation,
        variables: { input: },
      )

      expect_forbidden_error(result)
    end
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
end
