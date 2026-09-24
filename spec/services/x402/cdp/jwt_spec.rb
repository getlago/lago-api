# frozen_string_literal: true

require "rails_helper"

RSpec.describe X402::Cdp::Jwt do
  subject(:token) do
    described_class.generate(api_key_id: "key-id", api_key_secret:, request_method: "POST",
      request_host: "api.cdp.coinbase.com", request_path: "/platform/v2/x402/verify")
  end

  context "with an Ed25519 secret" do
    let(:signing_key) { OpenSSL::PKey.generate_key("ED25519") }
    let(:api_key_secret) { Base64.strict_encode64(signing_key.raw_private_key + signing_key.raw_public_key) }

    it "signs an EdDSA token bound to the request" do
      signing_input, _, signature = token.rpartition(".")
      header, claims = signing_input.split(".").map { |part| JSON.parse(Base64.urlsafe_decode64(part)) }

      expect(signing_key.verify(nil, Base64.urlsafe_decode64(signature), signing_input)).to be(true)
      expect(header).to include("alg" => "EdDSA", "kid" => "key-id", "typ" => "JWT")
      expect(claims).to include("sub" => "key-id", "iss" => "cdp", "aud" => ["cdp_service"], "uri" => "POST api.cdp.coinbase.com/platform/v2/x402/verify")
    end
  end

  context "with an ECDSA secret" do
    let(:signing_key) { OpenSSL::PKey::EC.generate("prime256v1") }
    let(:api_key_secret) { signing_key.to_pem }

    it "signs an ES256 token bound to the request" do
      claims, header = JWT.decode(token, signing_key, true, algorithm: "ES256")

      expect(header).to include("alg" => "ES256", "kid" => "key-id")
      expect(claims).to include("sub" => "key-id", "uri" => "POST api.cdp.coinbase.com/platform/v2/x402/verify")
    end
  end
end
