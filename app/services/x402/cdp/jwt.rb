# frozen_string_literal: true

module X402
  module Cdp
    # Bearer JWT for a CDP Secret API Key, bound to one request (method + host + path), valid two minutes.
    # Format per https://docs.cdp.coinbase.com/api-reference/v2/authentication. jwt 3.x has no EdDSA without an
    # extra gem, so Ed25519 tokens are signed with OpenSSL directly.
    class Jwt
      TTL = 120

      def self.generate(**)
        new(**).generate
      end

      def initialize(api_key_id:, api_key_secret:, request_method:, request_host:, request_path:)
        @api_key_id = api_key_id
        @api_key_secret = api_key_secret.to_s.strip.gsub("\\n", "\n")
        @request_method = request_method
        @request_host = request_host
        @request_path = request_path
      end

      def generate
        if ed25519?
          encode_ed25519
        else
          ::JWT.encode(claims, OpenSSL::PKey.read(api_key_secret), "ES256", header_fields)
        end
      end

      private

      attr_reader :api_key_id, :api_key_secret, :request_method, :request_host, :request_path

      def claims
        now = Time.current.to_i

        {
          sub: api_key_id,
          iss: "cdp",
          aud: ["cdp_service"],
          nbf: now,
          iat: now,
          exp: now + TTL,
          uri: "#{request_method.to_s.upcase} #{request_host}#{request_path}"
        }
      end

      def header_fields
        {kid: api_key_id, typ: "JWT", nonce: SecureRandom.hex(16)}
      end

      # CDP's default key type: base64 of 64 bytes, seed first.
      def ed25519?
        !api_key_secret.include?("BEGIN") && Base64.decode64(api_key_secret).bytesize == 64
      end

      def encode_ed25519
        header = {alg: "EdDSA"}.merge(header_fields)
        signing_input = [header, claims].map { |part| Base64.urlsafe_encode64(part.to_json, padding: false) }.join(".")
        seed = Base64.decode64(api_key_secret).byteslice(0, 32)
        signature = OpenSSL::PKey.new_raw_private_key("ED25519", seed).sign(nil, signing_input)

        "#{signing_input}.#{Base64.urlsafe_encode64(signature, padding: false)}"
      end
    end
  end
end
