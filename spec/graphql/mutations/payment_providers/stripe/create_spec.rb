# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::PaymentProviders::Stripe::Create, type: :graphql do
  let(:membership) { create(:membership) }

  let(:mutation) do
    <<-GQL
      mutation($input: AddStripePaymentProviderInput!) {
        addStripePaymentProvider(input: $input) {
          id,
          secretKey,
          code,
          name,
          successRedirectUrl
        }
      }
    GQL
  end

  let(:code) { 'stripe_1' }
  let(:name) { 'Stripe 1' }
  let(:secret_key) { 'sk_12345678901234567890' }
  let(:success_redirect_url) { Faker::Internet.url }

  it 'creates a stripe provider' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: membership.organization,
      query: mutation,
      variables: {
        input: {
          secretKey: secret_key,
          code:,
          name:,
          successRedirectUrl: success_redirect_url,
        },
      },
    )

    result_data = result['data']['addStripePaymentProvider']

    aggregate_failures do
      expect(result_data['id']).to be_present
      expect(result_data['secretKey']).to eq('••••••••…890')
      expect(result_data['code']).to eq(code)
      expect(result_data['name']).to eq(name)
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
            code:,
            name:,
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
            code:,
            name:,
          },
        },
      )

      expect_forbidden_error(result)
    end
  end
end
