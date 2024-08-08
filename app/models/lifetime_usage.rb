# frozen_string_literal: true

class LifetimeUsage < ApplicationRecord
  include Currencies
  include Discard::Model
  self.discard_column = :deleted_at

  belongs_to :organization

  validates :currency, inclusion: {in: currency_list}

  validates :current_usage_amount_cents, numericality: {greater_than_or_equal_to: 0}
  validates :invoiced_usage_amount_cents, numericality: {greater_than_or_equal_to: 0}

  monetize :current_usage_amount_cents,
    :invoiced_usage_amount_cents,
    with_model_currency: :currency

  default_scope -> { kept }

  def subscription
    Subscription.active
      .joins(:organization)
      .where(organizations: {id: organization_id})
      .where(external_id: external_subscription_id)
      .sole
  end
end
