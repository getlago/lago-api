# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::Subscriptions::Terminate, type: :graphql do
  let(:required_permission) { 'subscriptions:update' }
  let(:membership) { create(:membership) }
  let(:subscription) { create(:subscription, organization: membership.organization) }
  let(:mutation) do
    <<~GQL
      mutation($input: TerminateSubscriptionInput!) {
        terminateSubscription(input: $input) {
          id,
          status,
          terminatedAt
        }
      }
    GQL
  end

  it_behaves_like 'requires current user'
  it_behaves_like 'requires current organization'
  it_behaves_like 'requires permission', 'subscriptions:update'

  it 'terminates a subscription' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: membership.organization,
      permissions: required_permission,
      query: mutation,
      variables: {
        input: {
          id: subscription.id,
        },
      },
    )

    result_data = result['data']['terminateSubscription']

    aggregate_failures do
      expect(result_data['id']).to eq(subscription.id)
      expect(result_data['status']).to eq('terminated')
      expect(result_data['terminatedAt']).to be_present
    end
  end
end
