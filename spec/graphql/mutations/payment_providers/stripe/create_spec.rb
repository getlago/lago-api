# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::PaymentProviders::Stripe::Create, type: :graphql do
  let(:required_permission) { 'organization:integrations:create' }
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

  it_behaves_like 'requires current user'
  it_behaves_like 'requires current organization'
  it_behaves_like 'requires permission', 'organization:integrations:create'

  it 'creates a stripe provider' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: membership.organization,
      permissions: required_permission,
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
end
