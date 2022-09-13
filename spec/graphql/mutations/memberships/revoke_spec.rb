# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::Memberships::Revoke, type: :graphql do
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  let(:mutation) do
    <<-GQL
      mutation($input: RevokeMembershipInput!) {
        revokeMembership(input: $input) {
          id
          revokedAt
        }
      }
    GQL
  end

  it 'Revokes a membership' do
    user = create(:user)

    result = execute_graphql(
      current_user: user,
      query: mutation,
      variables: {
        input: { id: membership.id },
      },
    )

    data = result['data']['revokeMembership']

    expect(data['id']).to eq(membership.id)
    expect(data['revokedAt']).to be_present
  end

  it 'Cannot Revoke my own membership' do
    result = execute_graphql(
      current_user: membership.user,
      query: mutation,
      variables: {
        input: { id: membership.id },
      },
    )

    aggregate_failures do
      expect(result['errors'].first['message']).to eq('Method Not Allowed')
      expect(result['errors'].first['extensions']['code']).to eq('cannot_revoke_own_membership')
      expect(result['errors'].first['extensions']['status']).to eq(405)
    end
  end
end
