# frozen_string_literal: true

class SubscriptionActivationRule < ApplicationRecord
  belongs_to :subscription
  belongs_to :organization

  RULE_TYPES = %w[payment_required].freeze
  STATUSES = %w[pending satisfied failed not_applicable expired].freeze

  validates :rule_type, presence: true, inclusion: {in: RULE_TYPES}
  validates :status, presence: true, inclusion: {in: STATUSES}
  validates :timeout_hours, numericality: {only_integer: true, greater_than: 0}, allow_nil: true

  scope :pending, -> { where(status: "pending") }
  scope :failed, -> { where(status: "failed") }
  scope :satisfied, -> { where(status: "satisfied") }
end

# == Schema Information
#
# Table name: subscription_activation_rules
# Database name: primary
#
#  id              :uuid             not null, primary key
#  expires_at      :datetime
#  rule_type       :string           not null
#  status          :string           default("pending"), not null
#  timeout_hours   :integer
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  organization_id :uuid             not null
#  subscription_id :uuid             not null
#
# Indexes
#
#  index_activation_rules_on_subscription_and_type         (subscription_id,rule_type) UNIQUE
#  index_activation_rules_pending_with_expiry              (status,expires_at) WHERE (((status)::text = ANY ((ARRAY['pending'::character varying, 'failed'::character varying])::text[])) AND (expires_at IS NOT NULL))
#  index_subscription_activation_rules_on_organization_id  (organization_id)
#  index_subscription_activation_rules_on_subscription_id  (subscription_id)
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (subscription_id => subscriptions.id)
#
