# frozen_string_literal: true

class UsageThreshold < ApplicationRecord
  include PaperTrailTraceable
  include Currencies
  include Discard::Model
  self.discard_column = :deleted_at

  belongs_to :organization
  belongs_to :plan

  has_many :applied_usage_thresholds
  has_many :invoices, through: :applied_usage_thresholds

  monetize :amount_cents, with_currency: ->(threshold) { threshold.plan.amount_currency }

  validates :amount_cents, numericality: {greater_than: 0}
  validates :amount_cents, uniqueness: {scope: %i[plan_id recurring deleted_at]}, if: -> { deleted_at.nil? }
  validates :recurring, uniqueness: {scope: %i[plan_id deleted_at]}, if: -> { recurring? && deleted_at.nil? }

  scope :recurring, -> { where(recurring: true) }
  scope :not_recurring, -> { where(recurring: false) }

  default_scope -> { kept }

  def invoice_name
    threshold_display_name || I18n.t("invoice.usage_threshold")
  end
end

# == Schema Information
#
# Table name: usage_thresholds
#
#  id                     :uuid             not null, primary key
#  amount_cents           :bigint           not null
#  deleted_at             :datetime
#  recurring              :boolean          default(FALSE), not null
#  threshold_display_name :string
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  organization_id        :uuid             not null
#  plan_id                :uuid             not null
#
# Indexes
#
#  idx_on_amount_cents_plan_id_recurring_888044d66b  (amount_cents,plan_id,recurring) UNIQUE WHERE (deleted_at IS NULL)
#  index_usage_thresholds_on_organization_id         (organization_id)
#  index_usage_thresholds_on_plan_id                 (plan_id)
#  index_usage_thresholds_on_plan_id_and_recurring   (plan_id,recurring) UNIQUE WHERE ((recurring IS TRUE) AND (deleted_at IS NULL))
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (plan_id => plans.id)
#
