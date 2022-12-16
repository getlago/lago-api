# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::Subscriptions::Update, type: :graphql do
  let(:membership) { create(:membership) }

  let(:subscription) do
    create(
      :subscription,
      organization: membership.organization,
      subscription_at: Time.current + 3.days,
    )
  end

  let(:mutation) do
    <<-GQL
      mutation($input: UpdateSubscriptionInput!) {
        updateSubscription(input: $input) {
          id
          name
          subscriptionAt
          subscriptionDate
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
          name: 'New name',
        },
      },
    )

    result_data = result['data']['updateSubscription']

    aggregate_failures do
      expect(result_data['name']).to eq('New name')
    end
  end

  context 'with legacy subscription_date' do
    let(:subscription_at) { Time.current + 4.days }

    before { subscription.pending! }

    it 'updates an subscription' do
      result = execute_graphql(
        current_user: membership.user,
        query: mutation,
        variables: {
          input: {
            id: subscription.id,
            name: 'New name',
            subscriptionDate: subscription_at.to_date.iso8601,
          },
        },
      )

      result_data = result['data']['updateSubscription']

      aggregate_failures do
        expect(result_data['name']).to eq('New name')
        expect(result_data['subscriptionDate']).to eq(subscription_at.to_date.iso8601)
        expect(result_data['subscriptionAt']).to eq(subscription_at.beginning_of_day.iso8601)
      end
    end
  end

  context 'without current_user' do
    it 'returns an error' do
      result = execute_graphql(
        query: mutation,
        variables: {
          input: {
            id: subscription.id,
            name: 'New name',
          },
        },
      )

      expect_unauthorized_error(result)
    end
  end
end
