# frozen_string_literal: true

# A Standard Webhooks signing key (https://www.standardwebhooks.com): one ed25519 key
# pair for a webhook endpoint. An endpoint keeps several so a rotation can sign with the
# new and the old key at the same time (a key stays usable until its `expires_at` passes).
class WebhookEndpointSigningKey < ApplicationRecord
  PRIVATE_KEY_PREFIX = "whsk_"
  PUBLIC_KEY_PREFIX = "whpk_"

  belongs_to :organization
  belongs_to :webhook_endpoint

  encrypts :private_key

  validates :private_key, presence: true
  validates :public_key, presence: true

  before_validation :generate_key_pair, on: :create

  scope :usable, -> { where(expires_at: nil).or(where(arel_table[:expires_at].gt(Time.current))) }
  scope :expired, -> { where.not(expires_at: nil).where(arel_table[:expires_at].lteq(Time.current)) }

  # Returns the raw ed25519 signature bytes of `content`.
  def sign(content)
    raw = Base64.strict_decode64(private_key.delete_prefix(PRIVATE_KEY_PREFIX))
    OpenSSL::PKey.new_raw_private_key("ED25519", raw).sign(nil, content)
  end

  private

  def generate_key_pair
    return if private_key.present?

    key = OpenSSL::PKey.generate_key("ED25519")
    self.private_key = "#{PRIVATE_KEY_PREFIX}#{Base64.strict_encode64(key.raw_private_key)}"
    self.public_key = "#{PUBLIC_KEY_PREFIX}#{Base64.strict_encode64(key.raw_public_key)}"
  end
end

# == Schema Information
#
# Table name: webhook_endpoint_signing_keys
# Database name: primary
#
#  id                  :uuid             not null, primary key
#  expires_at          :datetime
#  private_key         :string           not null
#  public_key          :string           not null
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
