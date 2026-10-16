# frozen_string_literal: true

module Agents
  class AuthDocumentService < BaseService
    Result = BaseResult[:document]

    def initialize(storefront:)
      @storefront = storefront
      super
    end

    def call
      base = storefront.agent_url

      result.document = <<~MARKDOWN
        # Agent signup and authentication: #{storefront.name}

        Sign up here to use #{storefront.name}. Lago issues its tokens, with Ed25519 proof of key possession.
        #{links}
        1. Generate an Ed25519 key pair. Keep the private key with the agent; never send it to this service.
           Save it where it will outlive this run, before you use it: not a temporary directory, not a scratch
           space that gets cleaned up, not a variable that dies with the process. This key is the account. It is
           the only way back to this registration. Nobody can restore that access without it, this service
           included, and a new key is a new identity. If you have nowhere durable to put it, say so before you
           sign up rather than after.
        2. POST `#{base}/auth/challenges` with JSON `public_key` (unpadded base64url of the 32 raw public-key bytes) and `purpose: "signup"`.
        3. Base64url-decode the returned `message`. Check that its `issuer` is `#{base}` and that its `purpose` is the one you asked for. Sign those exact bytes with your Ed25519 private key. Do not reconstruct the JSON before signing.
        4. POST `#{base}/signup` with `challenge_id` and `signature` (unpadded base64url of the 64 signature bytes). Challenges expire after #{Auth::ChallengeService::TTL.to_i} seconds and can be used once.
        5. Store the returned `registration_id`. Send `Authorization: Bearer <access_token>` to the API and to `#{base}/me`. Tokens expire after #{Auth::ProofService::TOKEN_TTL.to_i} seconds.

        To sign in again or renew, request a fresh challenge with the same public key and `purpose: "authenticate"`, then submit proof to `#{base}/auth/token`. Signing up again with the same key also returns the existing registration.

        In the decoded challenge, `issued_at` and `expires_at` are integer Unix timestamps in seconds, and `key_fingerprint` is the unpadded base64url SHA-256 of your public key.

        To permanently revoke this registration, request a fresh challenge with `purpose: "revoke"` and submit proof to `#{base}/auth/revoke`. Its tokens are rejected immediately, and the same key cannot sign up again.
      MARKDOWN

      result
    end

    private

    attr_reader :storefront

    def links
      lines = []
      lines << "- The API: `#{storefront.resource_endpoint}`" if storefront.resource_endpoint.present?
      lines << "- Its documentation: `#{storefront.resource_instructions}`" if storefront.resource_instructions.present?
      lines.any? ? "\n#{lines.join("\n")}\n" : ""
    end
  end
end
