# frozen_string_literal: true

class Webhook < ApplicationRecord
  include RansackUuidSearch

  STATUS = %i[pending succeeded failed].freeze

  belongs_to :webhook_endpoint
  belongs_to :object, polymorphic: true, optional: true
  belongs_to :organization

  enum :status, STATUS

  def self.ransackable_attributes(_auth_object = nil)
    %w[id webhook_type]
  end

  # Up until 1.4.0, we stored the payload as a string. This method
  # ensures that we can still read the old payloads.
  # Webhooks created after 1.4.0 will have the payload stored as a hash.
  # Webhooks are deleted after 90 days, so we can remove this method 90 days after every client has updated to 1.4.0.
  def payload
    attr = super
    if attr.is_a?(String)
      JSON.parse(attr)
    else
      attr
    end
  end

  def generate_headers
    signature = case webhook_endpoint.signature_algo&.to_sym
    when :jwt
      jwt_signature
    when :hmac
      hmac_signature
    end

    {
      "X-Lago-Signature" => signature,
      "X-Lago-Signature-Algorithm" => webhook_endpoint.signature_algo.to_s,
      "X-Lago-Unique-Key" => id
    }
  end

  def jwt_signature
    JWT.encode(
      {
        data: payload.to_json,
        iss: issuer
      },
      RsaPrivateKey,
      "RS256"
    )
  end

  def hmac_signature
    hmac = OpenSSL::HMAC.digest("sha-256", organization.hmac_key, payload.to_json)
    Base64.strict_encode64(hmac)
  end

  def issuer
    ENV["LAGO_API_URL"]
  end
end

# == Schema Information
#
# Table name: webhooks
#
#  id                  :uuid             not null, primary key
#  endpoint            :string
#  http_status         :integer
#  last_retried_at     :datetime
#  object_type         :string
#  payload             :json
#  response            :json
#  retries             :integer          default(0), not null
#  status              :integer          default("pending"), not null
#  webhook_type        :string
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  object_id           :uuid
#  organization_id     :uuid             not null
#  webhook_endpoint_id :uuid
#
# Indexes
#
#  index_webhooks_on_organization_id      (organization_id)
#  index_webhooks_on_webhook_endpoint_id  (webhook_endpoint_id)
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (webhook_endpoint_id => webhook_endpoints.id)
#
