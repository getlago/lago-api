# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::WebhooksController, type: :request do
  let(:organization) { create(:organization) }

  describe "public_key" do
    it "returns the public key used to verify webhook signatures" do
      get_with_token(organization, "/api/v1/webhooks/public_key")

      expect(response).to have_http_status(:success)
      expect(response.body).to eq(Base64.encode64(RsaPublicKey.to_s))
    end
  end

  describe "json_public_key" do
    it "returns the public key in JSON response used to verify webhook signatures" do
      get_with_token(organization, "/api/v1/webhooks/json_public_key")

      expect(response).to have_http_status(:success)
      expect(json[:webhook][:public_key]).to eq(Base64.encode64(RsaPublicKey.to_s))
    end
  end
end
