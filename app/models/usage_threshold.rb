# frozen_string_literal: true

class UsageThreshold < ApplicationRecord
  include PaperTrailTraceable
  include Currencies
  include Discard::Model
  self.discard_column = :deleted_at

  belongs_to :plan

  monetize :amount_cents, with_currency: ->(threshold) { threshold.plan.amount_currency }

  validates :amount_cents, numericality: {greater_than: 0}
  validates :amount_cents, uniqueness: {scope: %i[plan_id recurring]}
  validates :recurring, uniqueness: {scope: :plan_id}, if: -> { recurring? }

  scope :recurring, -> { where(recurring: true) }
  scope :not_recurring, -> { where(recurring: false) }

  default_scope -> { kept }

  def invoice_name
    threshold_display_name || I18n.t('invoice.usage_threshold')
  end
end
