# frozen_string_literal: true

class Webhook < ApplicationRecord
  include RansackUuidSearch

  STATUS = %i[pending succeeded failed].freeze

  belongs_to :webhook_endpoint
  belongs_to :object, polymorphic: true, optional: true

  # TODO: Use relation to be able to eager load
  delegate :organization, to: :webhook_endpoint

  enum status: STATUS

  def self.ransackable_attributes(_auth_object = nil)
    %w[id webhook_type]
  end

  def generate_headers
    signature = case webhook_endpoint.signature_algo&.to_sym
    when :jwt
      jwt_signature
    when :hmac
      hmac_signature
    end

    {
      'X-Lago-Signature' => signature,
      'X-Lago-Signature-Algorithm' => webhook_endpoint.signature_algo.to_s,
      'X-Lago-Unique-Key' => id
    }
  end

  def jwt_signature
    JWT.encode(
      {
        data: payload.to_json,
        iss: issuer
      },
      RsaPrivateKey,
      'RS256',
    )
  end

  def hmac_signature
    hmac = OpenSSL::HMAC.digest('sha-256', organization.api_key, payload.to_json)
    Base64.strict_encode64(hmac)
  end

  def issuer
    ENV['LAGO_API_URL']
  end
end
