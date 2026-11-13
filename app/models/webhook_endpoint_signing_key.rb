# frozen_string_literal: true

class WebhookEndpointSigningKey < ApplicationRecord
  SECRET_PREFIX = "whsec_"
  SECRET_BYTES = 32

  belongs_to :organization
  belongs_to :webhook_endpoint

  encrypts :secret

  validates :secret, presence: true
  validate :organization_matches_endpoint

  before_validation :generate_secret, on: :create

  # Raw bytes the delivery signature is keyed with.
  def signing_secret
    Base64.strict_decode64(secret.delete_prefix(SECRET_PREFIX))
  end

  private

  def generate_secret
    self.secret ||= SECRET_PREFIX + Base64.strict_encode64(SecureRandom.random_bytes(SECRET_BYTES))
  end

  def organization_matches_endpoint
    if webhook_endpoint && organization_id != webhook_endpoint.organization_id
      errors.add(:organization, :must_belong_to_same_organization)
    end
  end
end

# == Schema Information
#
# Table name: webhook_endpoint_signing_keys
# Database name: primary
#
#  id                  :uuid             not null, primary key
#  secret              :text             not null
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
#  fk_rails_...  (webhook_endpoint_id => webhook_endpoints.id) ON DELETE => cascade
#
