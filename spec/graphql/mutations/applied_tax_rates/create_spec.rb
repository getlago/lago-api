# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::AppliedTaxRates::Create, type: :graphql do
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:mutation) do
    <<-GQL
      mutation($input: CreateAppliedTaxRateInput!) {
        createAppliedTaxRate(input: $input) {
          id
          taxRate { id }
          customer { id }
          createdAt
        }
      }
    GQL
  end

  let(:tax_rate) { create(:tax_rate, organization:) }
  let(:customer) { create(:customer, organization:) }

  it 'assigns a tax_rate to the customer' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      query: mutation,
      variables: {
        input: { taxRateId: tax_rate.id, customerId: customer.id },
      },
    )

    result_data = result['data']['createAppliedTaxRate']

    aggregate_failures do
      expect(result_data['id']).to be_present
      expect(result_data['taxRate']['id']).to eq(tax_rate.id)
      expect(result_data['customer']['id']).to eq(customer.id)
      expect(result_data['createdAt']).to be_present
    end
  end

  context 'without current user' do
    it 'returns an error' do
      result = execute_graphql(
        current_organization: organization,
        query: mutation,
        variables: {
          input: { taxRateId: tax_rate.id, customerId: customer.id },
        },
      )

      expect_unauthorized_error(result)
    end
  end

  context 'without current organization' do
    it 'returns an error' do
      result = execute_graphql(
        current_user: membership.user,
        query: mutation,
        variables: {
          input: { taxRateId: tax_rate.id, customerId: customer.id },
        },
      )

      expect_forbidden_error(result)
    end
  end
end
