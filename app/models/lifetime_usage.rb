# frozen_string_literal: true

class LifetimeUsage < ApplicationRecord
  include Currencies
  include Discard::Model
  self.discard_column = :deleted_at

  belongs_to :organization
  belongs_to :subscription

  validates :current_usage_amount_cents, numericality: {greater_than_or_equal_to: 0}
  validates :invoiced_usage_amount_cents, numericality: {greater_than_or_equal_to: 0}

  monetize :current_usage_amount_cents,
    :invoiced_usage_amount_cents,
    with_currency: ->(lifetime_usage) { lifetime_usage.subscription.plan.amount_currency }

  default_scope -> { kept }
end
