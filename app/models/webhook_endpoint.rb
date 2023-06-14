# frozen_string_literal: true

class WebhookEndpoint < ApplicationRecord
  LIMIT = 5

  belongs_to :organization
  has_many :webhooks

  validates :webhook_url, presence: true, url: true
  validate :max_webhook_endpoints, on: :create

  private

  def max_webhook_endpoints
    errors.add(:base, :exceeded_limit) if organization &&
                                          organization.webhook_endpoints.reload.count >= LIMIT
  end
end
