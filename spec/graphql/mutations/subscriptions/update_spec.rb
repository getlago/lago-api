# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::Subscriptions::Update, type: :graphql do
  let(:required_permission) { 'subscriptions:update' }
  let(:membership) { create(:membership) }

  let(:subscription) do
    create(
      :subscription,
      organization: membership.organization,
      subscription_at: Time.current + 3.days
    )
  end

  let(:mutation) do
    <<-GQL
      mutation($input: UpdateSubscriptionInput!) {
        updateSubscription(input: $input) {
          id
          name
          subscriptionAt
        }
      }
    GQL
  end

  it_behaves_like 'requires current user'
  it_behaves_like 'requires permission', 'subscriptions:update'

  it 'updates an subscription' do
    result = execute_graphql(
      current_user: membership.user,
      permissions: required_permission,
      query: mutation,
      variables: {
        input: {
          id: subscription.id,
          name: 'New name'
        }
      }
    )

    result_data = result['data']['updateSubscription']

    aggregate_failures do
      expect(result_data['name']).to eq('New name')
    end
  end
end
