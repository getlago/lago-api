# frozen_string_literal: true

require "rails_helper"

describe X402::Cdp::Jwt do
  subject(:token) do
    described_class.generate(api_key_id: "organizations/lago-test/apiKeys/x402", api_key_secret:, request_method:, request_host: "api.cdp.coinbase.com", request_path:)
  end

  let(:request_method) { "POST" }
  let(:request_path) { "/platform/v2/x402/settle" }

  def decode_parts(jwt)
    jwt.split(".").first(2).map { |part| JSON.parse(Base64.urlsafe_decode64(part)) }
  end

  context "with an Ed25519 secret, CDP's default" do
    let(:signing_key) { OpenSSL::PKey.generate_key("ED25519") }
    let(:api_key_secret) { Base64.strict_encode64(signing_key.raw_private_key + signing_key.raw_public_key) }

    before { freeze_time }

    it "is signed by the key" do
      signing_input, _, signature = token.rpartition(".")

      expect(signing_key.verify(nil, Base64.urlsafe_decode64(signature), signing_input)).to be(true)
    end

    it "carries an EdDSA header naming the key" do
      expect(decode_parts(token).first).to include("alg" => "EdDSA", "kid" => "organizations/lago-test/apiKeys/x402", "typ" => "JWT", "nonce" => match(/\A\h{32}\z/))
    end

    it "binds the claims to the request, for two minutes" do
      expect(decode_parts(token).last).to eq(
        "sub" => "organizations/lago-test/apiKeys/x402",
        "iss" => "cdp",
        "aud" => ["cdp_service"],
        "nbf" => Time.current.to_i,
        "iat" => Time.current.to_i,
        "exp" => Time.current.to_i + 120,
        "uri" => "POST api.cdp.coinbase.com/platform/v2/x402/settle"
      )
    end

    it "is a new token on every request" do
      expect(token).not_to eq(described_class.generate(api_key_id: "organizations/lago-test/apiKeys/x402", api_key_secret:, request_method:, request_host: "api.cdp.coinbase.com", request_path:))
    end

    context "with a GET" do
      let(:request_method) { "get" }
      let(:request_path) { "/platform/v2/x402/supported" }

      it "binds the method and path" do
        expect(decode_parts(token).last["uri"]).to eq("GET api.cdp.coinbase.com/platform/v2/x402/supported")
      end
    end
  end

  context "with an ECDSA secret" do
    let(:signing_key) { OpenSSL::PKey::EC.generate("prime256v1") }
    let(:api_key_secret) { signing_key.to_pem }

    it "signs an ES256 token" do
      claims, header = JWT.decode(token, signing_key, true, algorithm: "ES256")

      expect([header["kid"], claims["uri"]]).to eq(["organizations/lago-test/apiKeys/x402", "POST api.cdp.coinbase.com/platform/v2/x402/settle"])
    end

    context "when the PEM's newlines arrive escaped" do
      let(:api_key_secret) { signing_key.to_pem.gsub("\n", "\\n") }

      it "still signs" do
        expect { JWT.decode(token, signing_key, true, algorithm: "ES256") }.not_to raise_error
      end
    end
  end

  {
    "a plain string" => -> { "key-secret" },
    "an RSA key" => -> { OpenSSL::PKey::RSA.new(2048).to_pem },
    "a P-384 key" => -> { OpenSSL::PKey::EC.generate("secp384r1").to_pem },
    "a public EC key" => -> { OpenSSL::PKey::EC.generate("prime256v1").public_to_pem },
    "an Ed25519 PEM" => -> { OpenSSL::PKey.generate_key("ED25519").private_to_pem },
    "an encrypted PEM" => -> { OpenSSL::PKey::EC.generate("prime256v1").private_to_pem(OpenSSL::Cipher.new("aes-256-cbc"), "passphrase") },
    "nil" => -> {}
  }.each do |description, build_secret|
    context "with #{description} as the secret" do
      let(:api_key_secret) { build_secret.call }

      it "raises an invalid key error" do
        expect { token }.to raise_error(described_class::InvalidKeyError, /\Aunusable CDP API key secret: /)
      end
    end
  end

  context "with a secret that cannot be parsed" do
    let(:api_key_secret) { "key-secret" }

    it "keeps the secret out of the message" do
      expect { token }.to raise_error(described_class::InvalidKeyError, "unusable CDP API key secret: OpenSSL::PKey::PKeyError")
    end
  end
end
