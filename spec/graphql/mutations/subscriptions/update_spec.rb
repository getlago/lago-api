# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::Subscriptions::Update, type: :graphql do
  let(:membership) { create(:membership) }
  let(:subscription) { create(:subscription) }
  let(:mutation) do
    <<-GQL
      mutation($input: UpdateSubscriptionInput!) {
        updateSubscription(input: $input) {
          id,
          name
        }
      }
    GQL
  end

  it 'updates an subscription' do
    result = execute_graphql(
      current_user: membership.user,
      query: mutation,
      variables: {
        input: {
          id: subscription.id,
          name: 'New name'
        },
      },
    )

    result_data = result['data']['updateSubscription']

    aggregate_failures do
      expect(result_data['name']).to eq('New name')
    end
  end

  context 'without current_user' do
    it 'returns an error' do
      result = execute_graphql(
        query: mutation,
        variables: {
          input: {
            id: subscription.id,
            name: 'New name'
          },
        },
      )

      expect_unauthorized_error(result)
    end
  end
end
