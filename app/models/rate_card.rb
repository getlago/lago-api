# frozen_string_literal: true

class RateCard < ApplicationRecord
  include PaperTrailTraceable
  include Currencies
  include Discard::Model
  include CatalogAttachable

  self.discard_column = :deleted_at

  BILLING_TIMINGS = {
    arrears: "arrears",
    advance: "advance"
  }.freeze

  # none is a real value, not a nil stand-in: the column is NOT NULL so the API
  # always returns a concrete grouping behaviour.
  REGROUP_PAID_FEES = {
    none: "none",
    invoice: "invoice"
  }.freeze

  belongs_to :organization
  belongs_to :product
  belongs_to :product_filter, optional: true

  has_many :rates, class_name: "RateCardRate"
  has_many :plan_applied_rate_cards, class_name: "PlanRateCard"
  has_many :contract_applied_rate_cards, class_name: "ContractRateCard"
  has_many :applied_taxes, class_name: "RateCard::AppliedTax", dependent: :destroy
  has_many :taxes, through: :applied_taxes

  enum :billing_timing, BILLING_TIMINGS, validate: true
  # prefix: a bare `none` value would define a RateCard.none scope, which
  # collides with ActiveRecord::QueryMethods#none.
  enum :regroup_paid_fees, REGROUP_PAID_FEES, validate: true, prefix: true

  validates :name, presence: true
  validates :code,
    presence: true,
    uniqueness: {scope: :organization_id, conditions: -> { where(deleted_at: nil) }}
  # allow_nil keeps a missing currency on the presence error only; the
  # inclusion error fires for a provided-but-unknown currency.
  validates :currency, presence: true, inclusion: {in: currency_list, allow_nil: true}
  validate :validate_filter_belongs_to_item
  validate :validate_display_on_invoice
  validate :validate_proration
  validate :validate_regroup_paid_fees

  default_scope -> { kept }

  # A card scoped to a filter must price a slice of its own item.
  def validate_filter_belongs_to_item
    return if product_filter.nil?
    return if product_filter.product_id == product_id

    errors.add(:product_filter, :does_not_belong_to_product)
  end

  def validate_display_on_invoice
    return if advance? || display_on_invoice?

    errors.add(:display_on_invoice, :not_allowed_for_billing_timing)
  end

  # Usage proration spreads a recurring quantity across the period, so it
  # needs a recurring metric — and not weighted_sum, which prorates by design
  def validate_proration
    return unless proration?
    return unless product&.usage?

    metric = product.billable_metric
    return if metric.nil?

    errors.add(:proration, :requires_recurring_metric) unless metric.recurring?
    errors.add(:proration, :not_allowed_for_aggregation_type) if metric.weighted_sum_agg?
  end

  # Paid-fee regrouping only exists for advance fees kept off the invoice
  def validate_regroup_paid_fees
    return if regroup_paid_fees_none?

    errors.add(:regroup_paid_fees, :not_allowed_for_billing_timing) unless advance?
    errors.add(:regroup_paid_fees, :not_allowed_with_display_on_invoice) if display_on_invoice?
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[name code]
  end

  # The card bills someone once it belongs to a plan that has contracts or is
  # attached directly to a contract. From that point the billed timeline
  # freezes — card fields, active and past rates — and price changes go
  # through appended rates. The Subscription check stays for catalog plans
  # subscribed through v1 before contracts existed.
  def attached_to_subscriptions?
    contract_applied_rate_cards.exists? ||
      Contract.where(plan_id: plan_applied_rate_cards.select(:plan_id)).exists? ||
      Subscription.where(plan_id: plan_applied_rate_cards.select(:plan_id)).exists?
  end

  # The active rate is the latest effective rate; later rates are pending and
  # earlier ones have been superseded (terminated).
  def active_rate
    rates.effective.order(effective_from: :desc).first
  end
end

# == Schema Information
#
# Table name: rate_cards
# Database name: primary
#
#  id                        :uuid             not null, primary key
#  applied_pricing_unit_code :string
#  billing_timing            :enum             default("arrears"), not null
#  code                      :string           not null
#  currency                  :string           not null
#  deleted_at                :datetime
#  description               :string
#  display_on_invoice        :boolean          default(TRUE), not null
#  name                      :string           not null
#  proration                 :boolean          default(FALSE), not null
#  regroup_paid_fees         :enum             default("none"), not null
#  wallet_targetable         :boolean
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  organization_id           :uuid             not null
#  product_filter_id         :uuid
#  product_id                :uuid             not null
#
# Indexes
#
#  index_rate_cards_on_deleted_at                (deleted_at)
#  index_rate_cards_on_organization_id           (organization_id)
#  index_rate_cards_on_organization_id_and_code  (organization_id,code) UNIQUE WHERE (deleted_at IS NULL)
#  index_rate_cards_on_product_filter_id         (product_filter_id)
#  index_rate_cards_on_product_id                (product_id)
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (product_filter_id => product_filters.id)
#  fk_rails_...  (product_id => products.id)
#
