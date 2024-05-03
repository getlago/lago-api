# frozen_string_literal: true

class WebhookEndpoint < ApplicationRecord
  LIMIT = 5

  SIGNATURE_ALGOS = [
    :jwt,
    :hmac,
  ].freeze

  belongs_to :organization
  has_many :webhooks, dependent: :destroy

  validates :webhook_url, presence: true, url: true
  validates :webhook_url, uniqueness: { scope: :organization_id }
  validate :max_webhook_endpoints, on: :create

  enum signature_algo: SIGNATURE_ALGOS

  private

  def max_webhook_endpoints
    errors.add(:base, :exceeded_limit) if organization &&
      organization.webhook_endpoints.reload.count >= LIMIT
  end
end
