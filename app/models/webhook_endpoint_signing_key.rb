# frozen_string_literal: true

class WebhookEndpointSigningKey < ApplicationRecord
  SECRET_PREFIX = "whsec_"

  belongs_to :organization
  belongs_to :webhook_endpoint

  encrypts :secret_key

  before_validation :generate_secret_key, on: :create

  validates :secret_key, presence: true

  # Arel, not a SQL string: a raw string makes the query non-retryable on a dropped connection.
  scope :usable, -> { where(arel_table[:expires_at].eq(nil).or(arel_table[:expires_at].gt(Time.current))) }

  # Standard Webhooks signature: base64 HMAC-SHA256 keyed with the decoded secret.
  def sign(content)
    key = Base64.strict_decode64(secret_key.delete_prefix(SECRET_PREFIX))
    Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", key, content))
  end

  private

  def generate_secret_key
    self.secret_key ||= SECRET_PREFIX + Base64.strict_encode64(SecureRandom.bytes(24))
  end
end

# == Schema Information
#
# Table name: webhook_endpoint_signing_keys
# Database name: primary
#
#  id                  :uuid             not null, primary key
#  expires_at          :datetime
#  secret_key          :string           not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  organization_id     :uuid             not null
#  webhook_endpoint_id :uuid             not null
#
# Indexes
#
#  index_webhook_endpoint_signing_keys_on_organization_id      (organization_id)
#  index_webhook_endpoint_signing_keys_on_webhook_endpoint_id  (webhook_endpoint_id)
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (webhook_endpoint_id => webhook_endpoints.id)
#
