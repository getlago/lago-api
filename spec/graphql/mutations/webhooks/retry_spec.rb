# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::Webhooks::Retry, type: :graphql do
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:webhook) { create(:webhook, :failed, organization:) }

  let(:mutation) do
    <<-GQL
      mutation($input: RetryWebhookInput!) {
        retryWebhook(input: $input) {
          id,
        }
      }
    GQL
  end

  before { webhook }

  it 'retries a webhook' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      query: mutation,
      variables: {
        input: {
          id: webhook.id,
        },
      },
    )

    result_data = result['data']['retryWebhook']

    aggregate_failures do
      expect(result_data['id']).to eq(webhook.id)
    end
  end
end
