# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Resolvers::CurrentUserResolver, type: :graphql do
  let(:query) do
    <<~GRAPHQL
      query {
        currentUser {
          id
          email
        }
      }
    GRAPHQL
  end

  it 'returns current_user' do
    user = create(:user)

    result = execute_graphql(
      current_user: user,
      query: query
    )

    aggregate_failures do
      expect(result['data']['currentUser']['email']).to eq(user.email)
      expect(result['data']['currentUser']['id']).to eq(user.id)
    end
  end

  context 'with no current_user' do
    it 'returns an error' do
      result = execute_graphql(query: query)

      expect_unauthorized_error(result)
    end
  end
end
