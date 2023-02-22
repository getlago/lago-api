# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::Webhooks::Resend, type: :graphql do
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:webhook) { create(:webhook, :failed, organization:) }

  let(:mutation) do
    <<-GQL
      mutation($input: ResendWebhookInput!) {
        resendWebhook(input: $input) {
          id,
        }
      }
    GQL
  end

  before { webhook }

  it 'resends a webhook' do
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

    result_data = result['data']['resendWebhook']

    aggregate_failures do
      expect(result_data['id']).to eq(webhook.id)
    end
  end
end
