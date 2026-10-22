# frozen_string_literal: true

# A Standard Webhooks signing key (https://www.standardwebhooks.com): one `v1` HMAC secret
# for a webhook endpoint. An endpoint keeps several so a rotation can sign with the new and
# the old secret at the same time (a secret stays usable until its `expires_at` passes).
class WebhookEndpointSigningKey < ApplicationRecord
  SECRET_PREFIX = "whsec_"

  belongs_to :organization
  belongs_to :webhook_endpoint

  encrypts :secret

  validates :secret, presence: true

  before_validation :generate_secret, on: :create

  scope :usable, -> { where(expires_at: nil).or(where(arel_table[:expires_at].gt(Time.current))) }
  scope :expired, -> { where.not(expires_at: nil).where(arel_table[:expires_at].lteq(Time.current)) }

  # Returns the raw HMAC-SHA256 digest of `content` under this secret.
  def sign(content)
    key = Base64.strict_decode64(secret.delete_prefix(SECRET_PREFIX))
    OpenSSL::HMAC.digest("SHA256", key, content)
  end

  private

  def generate_secret
    return if secret.present?

    # 24 random bytes, base64 encoded, as the spec defines for a `whsec_` secret.
    self.secret = "#{SECRET_PREFIX}#{Base64.strict_encode64(SecureRandom.bytes(24))}"
  end
end

# == Schema Information
#
# Table name: webhook_endpoint_signing_keys
# Database name: primary
#
#  id                  :uuid             not null, primary key
#  expires_at          :datetime
#  secret              :string           not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  organization_id     :uuid             not null
#  webhook_endpoint_id :uuid             not null
#
# Indexes
#
#  index_webhook_endpoint_signing_keys_on_expires_at           (expires_at)
#  index_webhook_endpoint_signing_keys_on_organization_id      (organization_id)
#  index_webhook_endpoint_signing_keys_on_webhook_endpoint_id  (webhook_endpoint_id)
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (webhook_endpoint_id => webhook_endpoints.id)
#
