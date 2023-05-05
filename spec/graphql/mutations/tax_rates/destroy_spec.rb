# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::TaxRates::Destroy, type: :graphql do
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:tax_rate) { create(:tax_rate, organization:) }

  let(:mutation) do
    <<-GQL
      mutation($input: DestroyTaxRateInput!) {
        destroyTaxRate(input: $input) { id }
      }
    GQL
  end

  before { tax_rate }

  it 'destroys a tax rate' do
    expect do
      execute_graphql(
        current_user: membership.user,
        current_organization: membership.organization,
        query: mutation,
        variables: { input: { id: tax_rate.id } },
      )
    end.to change(TaxRate, :count).by(-1)
  end

  context 'without current_organization' do
    it 'returns an error' do
      result = execute_graphql(
        current_user: membership.user,
        query: mutation,
        variables: { input: { id: tax_rate.id } },
      )

      expect_forbidden_error(result)
    end
  end

  context 'without current_user' do
    it 'returns an error' do
      result = execute_graphql(
        current_organization: membership.organization,
        query: mutation,
        variables: { input: { id: tax_rate.id } },
      )

      expect_unauthorized_error(result)
    end
  end
end
