# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::LoginUser, type: :graphql do
  let(:mutation) do
    <<~GQL
      mutation($input: LoginUserInput!) {
        loginUser(input: $input) {
          token
          user {
            id
            email
          }
        }
      }
    GQL
  end

  it 'returns token and user' do
    user = create(:user)
    create(:membership, user: user)

    result = execute_graphql(
      query: mutation,
      variables: {
        input: {
          email: user.email,
          password: 'ILoveLago'
        }
      }
    )

    result_data = result['data']['loginUser']

    aggregate_failures do
      expect(result_data['token']).to be_present
      expect(result_data['user']['id']).to eq(user.id)
    end
  end

  context 'with bad credentials' do
    it 'returns an error' do
      user = create(:user)

      result = execute_graphql(
        query: mutation,
        variables: {
          input: {
            email: user.email,
            password: 'badpassword'
          }
        }
      )

      aggregate_failures do
        expect(result['errors'].first['message']).to eq('incorrect_login_or_password')
      end
    end
  end
end
