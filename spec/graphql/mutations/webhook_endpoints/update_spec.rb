# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::WebhookEndpoints::Update, type: :graphql do
  let(:membership) { create(:membership) }
  let(:webhook_url) { Faker::Internet.url }
  let(:webhook_endpoint) { create(:webhook_endpoint, organization: membership.organization) }

  let(:input) do
    {
      id: webhook_endpoint.id,
      webhookUrl: webhook_url,
      signatureAlgo: 'hmac',
    }
  end

  let(:mutation) do
    <<-GQL
      mutation($input: WebhookEndpointUpdateInput!) {
        updateWebhookEndpoint(input: $input) {
          id,
          webhookUrl,
          signatureAlgo,
        }
      }
    GQL
  end

  before { webhook_endpoint }

  it 'updates a webhook_endpoint' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: membership.organization,
      query: mutation,
      variables: { input: },
    )

    expect(result['data']['updateWebhookEndpoint']).to include(
      'id' => String,
      'webhookUrl' => webhook_url,
      'signatureAlgo' => 'hmac',
    )
  end

  context 'without current user' do
    it 'returns an error' do
      result = execute_graphql(
        current_organization: membership.organization,
        query: mutation,
        variables: { input: },
      )

      expect_unauthorized_error(result)
    end
  end

  context 'without current organization' do
    it 'returns an error' do
      result = execute_graphql(
        current_user: membership.user,
        query: mutation,
        variables: { input: },
      )

      expect_forbidden_error(result)
    end
  end
end
