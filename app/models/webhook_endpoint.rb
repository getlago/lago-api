# frozen_string_literal: true

class WebhookEndpoint < ApplicationRecord
  LIMIT = 10

  SIGNATURE_ALGOS = [
    :jwt,
    :hmac
  ].freeze

  belongs_to :organization
  has_many :webhooks, dependent: :delete_all

  validates :webhook_url, presence: true, url: true
  validates :webhook_url, uniqueness: {scope: :organization_id}
  validate :max_webhook_endpoints, on: :create

  enum :signature_algo, SIGNATURE_ALGOS

  def self.ransackable_attributes(_auth_object = nil)
    %w[webhook_url]
  end

  private

  def max_webhook_endpoints
    errors.add(:base, :exceeded_limit) if organization &&
      organization.webhook_endpoints.reload.count >= LIMIT
  end
end

# == Schema Information
#
# Table name: webhook_endpoints
#
#  id              :uuid             not null, primary key
#  signature_algo  :integer          default("jwt"), not null
#  webhook_url     :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  organization_id :uuid             not null
#
# Indexes
#
#  index_webhook_endpoints_on_organization_id                  (organization_id)
#  index_webhook_endpoints_on_webhook_url_and_organization_id  (webhook_url,organization_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#
