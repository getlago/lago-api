# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::PaymentProviders::Pinet::Create, type: :graphql do
  let(:membership) { create(:membership) }

  let(:mutation) do
    <<-GQL
      mutation($input: AddPinetPaymentProviderInput!) {
        addPinetPaymentProvider(input: $input) {
          id,
          secretKey,
          createCustomers,
          successRedirectUrl
        }
      }
    GQL
  end

  let(:secret_key) { 'api_key_12345678901234567890' }
  let(:success_redirect_url) { Faker::Internet.url }

  it 'creates a pinet provider' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: membership.organization,
      query: mutation,
      variables: {
        input: {
          secretKey: secret_key,
          createCustomers: false,
          successRedirectUrl: success_redirect_url,
        },
      },
    )

    result_data = result['data']['addPinetPaymentProvider']

    aggregate_failures do
      expect(result_data['id']).to be_present
      expect(result_data['secretKey']).to eq('••••••••…890')
      expect(result_data['createCustomers']).to eq(false)
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
            secretKey: secret_key,
            createCustomers: false,
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
            secretKey: secret_key,
            createCustomers: false,
          },
        },
      )

      expect_forbidden_error(result)
    end
  end
end
