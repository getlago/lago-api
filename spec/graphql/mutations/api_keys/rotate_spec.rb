# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::ApiKeys::Rotate, type: :graphql do
  subject(:result) do
    execute_graphql(
      current_user: membership.user,
      current_organization: membership.organization,
      permissions: required_permission,
      query:,
      variables: {input: {id: api_key.id}}
    )
  end

  let(:query) do
    <<-GQL
      mutation($input: RotateApiKeyInput!) {
        rotateApiKey(input: $input) { id value createdAt }
      }
    GQL
  end

  let(:required_permission) { 'developers:keys:manage' }
  let!(:membership) { create(:membership) }

  it_behaves_like 'requires current user'
  it_behaves_like 'requires current organization'
  it_behaves_like 'requires permission', 'developers:keys:manage'

  context 'when api key with such ID exists in the current organization' do
    let(:api_key) { membership.organization.api_keys.first }

    it 'expires the api key' do
      expect { result }.to change { api_key.reload.expires_at }.from(nil).to(Time)
    end

    it 'returns newly created api key' do
      api_key_response = result['data']['rotateApiKey']
      new_api_key = membership.organization.api_keys.last

      aggregate_failures do
        expect(api_key_response['id']).to eq(new_api_key.id)
        expect(api_key_response['value']).to eq(new_api_key.value)
        expect(api_key_response['createdAt']).to eq(new_api_key.created_at.iso8601)
        expect(api_key_response['expiresAt']).to be_nil
      end
    end
  end

  context 'when api key with such ID does not exist in the current organization' do
    let!(:api_key) { create(:api_key) }

    it 'does not change the api key' do
      expect { result }.not_to change { api_key.reload.expires_at }
    end

    it 'does not create an api key' do
      expect { result }.not_to change(ApiKey, :count)
    end

    it 'returns an error' do
      expect_graphql_error(result:, message: 'Resource not found')
    end
  end
end
