# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::AddOns::Update, type: :graphql do
  let(:membership) { create(:membership) }
  let(:add_on) { create(:add_on, organization: membership.organization) }
  let(:mutation) do
    <<-GQL
      mutation($input: UpdateAddOnInput!) {
        updateAddOn(input: $input) {
          id,
          name,
          code,
          description,
          amountCents,
          amountCurrency
        }
      }
    GQL
  end

  it 'updates an add-on' do
    result = execute_graphql(
      current_user: membership.user,
      query: mutation,
      variables: {
        input: {
          id: add_on.id,
          name: 'New name',
          code: 'new_code',
          description: 'desc',
          amountCents: 123,
          amountCurrency: 'USD'
        },
      },
    )

    result_data = result['data']['updateAddOn']

    aggregate_failures do
      expect(result_data['name']).to eq('New name')
      expect(result_data['code']).to eq('new_code')
      expect(result_data['description']).to eq('desc')
      expect(result_data['amountCents']).to eq(123)
      expect(result_data['amountCurrency']).to eq('USD')
    end
  end

  context 'without current_user' do
    it 'returns an error' do
      result = execute_graphql(
        query: mutation,
        variables: {
          input: {
            id: add_on.id,
            name: 'New name',
            code: 'new_code',
            amountCents: 123,
            amountCurrency: 'USD'
          },
        },
      )

      expect_unauthorized_error(result)
    end
  end
end
