# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::Customers::Destroy, type: :graphql do
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }

  let(:mutation) do
    <<-GQL
      mutation($input: DestroyCustomerInput!) {
        destroyCustomer(input: $input) {
          id
        }
      }
    GQL
  end

  it 'deletes a customer' do
    result = execute_graphql(
      current_user: membership.user,
      query: mutation,
      variables: {
        input: { id: customer.id },
      },
    )

    data = result['data']['destroyCustomer']
    expect(data['id']).to eq(customer.id)
  end

  context 'without current_user' do
    it 'returns an error' do
      result = execute_graphql(
        query: mutation,
        variables: {
          input: { id: customer.id },
        },
      )

      expect_unauthorized_error(result)
    end
  end
end
