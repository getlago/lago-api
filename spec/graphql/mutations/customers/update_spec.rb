# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::Customers::Update, type: :graphql do
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization: organization) }

  let(:mutation) do
    <<~GQL
      mutation($input: UpdateCustomerInput!) {
        updateCustomer(input: $input) {
          id,
          name,
          customerId
        }
      }
    GQL
  end

  it 'updates a customer' do
    customer_id = SecureRandom.uuid

    result = execute_graphql(
      current_user: membership.user,
      query: mutation,
      variables: {
        input: {
          id: customer.id,
          name: 'Updated customer',
          customerId: customer_id,
        },
      },
    )

    result_data = result['data']['updateCustomer']

    aggregate_failures do
      expect(result_data['id']).to be_present
      expect(result_data['name']).to eq('Updated customer')
      expect(result_data['customerId']).to eq(customer_id)
    end
  end

  context 'without current user' do
    it 'returns an error' do
      result = execute_graphql(
        query: mutation,
        variables: {
          input: {
            id: customer.id,
            name: 'Updated customer',
            customerId: SecureRandom.uuid,
          },
        },
      )

      expect_unauthorized_error(result)
    end
  end
end
