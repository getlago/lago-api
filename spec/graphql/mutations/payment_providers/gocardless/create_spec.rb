# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::PaymentProviders::Gocardless::Create, type: :graphql do
  let(:membership) { create(:membership) }
  let(:access_code) { 'ert_123456_abc' }
  let(:oauth_client) { instance_double(OAuth2::Client) }
  let(:auth_code_strategy) { instance_double(OAuth2::Strategy::AuthCode) }
  let(:access_token) { instance_double(OAuth2::AccessToken) }
  let(:success_redirect_url) { Faker::Internet.url }

  let(:mutation) do
    <<-GQL
      mutation($input: AddGocardlessPaymentProviderInput!) {
        addGocardlessPaymentProvider(input: $input) {
          id,
          hasAccessToken,
          successRedirectUrl
        }
      }
    GQL
  end

  before do
    allow(OAuth2::Client).to receive(:new)
      .and_return(oauth_client)
    allow(oauth_client).to receive(:auth_code)
      .and_return(auth_code_strategy)
    allow(auth_code_strategy).to receive(:get_token)
      .and_return(access_token)
    allow(access_token).to receive(:token)
      .and_return('access_token_554')
  end

  it 'creates a gocardless provider' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: membership.organization,
      query: mutation,
      variables: {
        input: {
          accessCode: access_code,
          successRedirectUrl: success_redirect_url,
        },
      },
    )

    result_data = result['data']['addGocardlessPaymentProvider']

    aggregate_failures do
      expect(result_data['id']).to be_present
      expect(result_data['hasAccessToken']).to be(true)
      expect(result_data['successRedirectUrl']).to eq(success_redirect_url)
    end
  end

  context 'without current user' do
    it 'returns an error' do
      result = execute_graphql(
        current_organization: membership.organization,
        query: mutation,
        variables: {
          input: {
            accessCode: access_code,
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
            accessCode: access_code,
          },
        },
      )

      expect_forbidden_error(result)
    end
  end
end
