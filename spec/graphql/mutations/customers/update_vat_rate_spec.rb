# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::Customers::UpdateVatRate, type: :graphql do
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization: organization) }

  let(:mutation) do
    <<~GQL
      mutation($input: UpdateCustomerVatRateInput!) {
        updateCustomerVatRate(input: $input) {
          id,
          name,
          externalId,
          vatRate
        }
      }
    GQL
  end

  it 'updates a customer' do
    result = execute_graphql(
      current_user: membership.user,
      query: mutation,
      variables: {
        input: {
          id: customer.id,
          vatRate: 12.5,
        },
      },
    )

    result_data = result['data']['updateCustomerVatRate']

    aggregate_failures do
      expect(result_data['id']).to be_present
      expect(result_data['vatRate']).to eq(12.5)
    end
  end

  context 'without current user' do
    it 'returns an error' do
      result = execute_graphql(
        query: mutation,
        variables: {
          input: {
            id: customer.id,
            vatRate: 12.5,
          },
        },
      )

      expect_unauthorized_error(result)
    end
  end
end
