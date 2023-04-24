# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Resolvers::CurrentUserResolver, type: :graphql do
  let(:query) do
    <<~GRAPHQL
      query {
        currentUser {
          id
          email
          premium
          organizations {
            id
          }
        }
      }
    GRAPHQL
  end

  it 'returns current_user' do
    user = create(:user)

    result = execute_graphql(
      current_user: user,
      query:,
    )

    aggregate_failures do
      expect(result['data']['currentUser']['email']).to eq(user.email)
      expect(result['data']['currentUser']['id']).to eq(user.id)
      expect(result['data']['currentUser']['premium']).to be_falsey
    end
  end

  describe 'with revoked membership' do
    let(:membership) { create(:membership) }
    let(:revoked_membership) do
      create(:membership, user: membership.user, status: :revoked)
    end

    before { revoked_membership }

    it 'only lists organizations when membership has an active status' do
      result = execute_graphql(
        current_user: membership.user,
        query:,
      )

      expect(result['data']['currentUser']['organizations']).not_to include(revoked_membership.organization)
    end
  end

  context 'with no current_user' do
    it 'returns an error' do
      result = execute_graphql(query:)

      expect_unauthorized_error(result)
    end
  end
end
