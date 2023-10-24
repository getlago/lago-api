# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::PaymentProviders::Adyen::Update, type: :graphql do
  let(:membership) { create(:membership) }
  let(:adyen_provider) { create(:adyen_provider, organization: membership.organization) }
  let(:success_redirect_url) { Faker::Internet.url }

  let(:mutation) do
    <<-GQL
      mutation($input: UpdateAdyenPaymentProviderInput!) {
        updateAdyenPaymentProvider(input: $input) {
          id,
          successRedirectUrl
        }
      }
    GQL
  end

  before { adyen_provider }

  it 'updates an adyen provider' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: membership.organization,
      query: mutation,
      variables: {
        input: {
          successRedirectUrl: success_redirect_url,
        },
      },
    )

    result_data = result['data']['updateAdyenPaymentProvider']

    expect(result_data['successRedirectUrl']).to eq(success_redirect_url)
  end

  context 'without current user' do
    it 'returns an error' do
      result = execute_graphql(
        current_organization: membership.organization,
        query: mutation,
        variables: {
          input: {
            successRedirectUrl: success_redirect_url,
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
            successRedirectUrl: success_redirect_url,
          },
        },
      )

      expect_forbidden_error(result)
    end
  end
end
