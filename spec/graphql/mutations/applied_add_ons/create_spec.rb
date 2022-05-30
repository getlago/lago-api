# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::AppliedAddOns::Create, type: :graphql do
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:mutation) do
    <<-GQL
      mutation($input: CreateAppliedAddOnInput!) {
        createAppliedAddOn(input: $input) {
          addOn { id name }
          id,
          amountCents,
          amountCurrency,
          createdAt
        }
      }
    GQL
  end

  let(:add_on) { create(:add_on, organization: organization) }
  let(:customer) { create(:customer, organization: organization) }

  before { create(:active_subscription, customer: customer) }

  it 'assigns an add-on to the customer' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      query: mutation,
      variables: {
        input: {
          addOnId: add_on.id,
          customerId: customer.id,
          amountCents: 123,
          amountCurrency: 'EUR',
        },
      },
    )

    result_data = result['data']['createAppliedAddOn']

    aggregate_failures do
      expect(result_data['id']).to be_present
      expect(result_data['addOn']['id']).to eq(add_on.id)
      expect(result_data['addOn']['name']).to eq(add_on.name)
      expect(result_data['amountCents']).to eq(123)
      expect(result_data['amountCurrency']).to eq('EUR')
      expect(result_data['createdAt']).to be_present
    end
  end

  context 'without current user' do
    it 'returns an error' do
      result = execute_graphql(
        current_organization: organization,
        query: mutation,
        variables: {
          input: {
            addOnId: add_on.id,
            customerId: customer.id,
            amountCents: 123,
            amountCurrency: 'EUR',
          },
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
          input: {
            addOnId: add_on.id,
            customerId: customer.id,
            amountCents: 123,
            amountCurrency: 'EUR',
          },
        },
      )

      expect_forbidden_error(result)
    end
  end
end
