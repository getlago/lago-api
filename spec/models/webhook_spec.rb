# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Webhook, type: :model do
  subject(:webhook) { create(:webhook) }

  let(:organization) { create(:organization, name: "sefsefs", api_key: 'the_key') }

  it { is_expected.to belong_to(:webhook_endpoint) }
  it { is_expected.to belong_to(:object).optional }

  describe '#generate_headers' do
    it 'generates the query headers' do
      headers = webhook.generate_headers

      expect(headers).to have_key('X-Lago-Signature')
      expect(headers).to have_key('X-Lago-Signature-Algorithm')
      expect(headers).to have_key('X-Lago-Unique-Key')
      expect(headers['X-Lago-Signature-Algorithm']).to eq('jwt')
      expect(headers['X-Lago-Unique-Key']).to eq(webhook.id)
    end
  end

  describe '#jwt_signature' do
    it 'generates a correct jwt signature' do
      decoded_signature = JWT.decode(
        webhook.jwt_signature,
        RsaPublicKey,
        true,
        {
          algorithm: 'RS256',
          iss: ENV['LAGO_API_URL'],
          verify_iss: true
        },
      )

      expect(decoded_signature).to eq([{"data" => webhook.payload.to_json, "iss" => "https://api.lago.dev"}, {"alg" => "RS256"}])
    end
  end

  describe '#hmac_signature' do
    it 'generates a correct hmac signature' do
      webhook.webhook_endpoint.organization.api_key = 'the_key'
      hmac = OpenSSL::HMAC.digest('sha-256', 'the_key', webhook.payload.to_json)
      base64_hmac = Base64.strict_encode64(hmac)

      expect(base64_hmac).to eq(webhook.hmac_signature)
    end
  end
end
