# frozen_string_literal: true

class RateCard < ApplicationRecord
  include PaperTrailTraceable
  include Currencies
  include Discard::Model

  self.discard_column = :deleted_at

  BILLING_TIMINGS = {
    arrears: "arrears",
    advance: "advance"
  }.freeze

  REGROUP_PAID_FEES = {
    invoice: "invoice"
  }.freeze

  belongs_to :organization
  belongs_to :product_item
  belongs_to :product_item_filter, optional: true

  has_many :rates, class_name: "RateCardRate"
  has_many :plan_rate_cards
  has_many :subscription_rate_cards

  enum :billing_timing, BILLING_TIMINGS, validate: true
  enum :regroup_paid_fees, REGROUP_PAID_FEES, validate: {allow_nil: true}

  validates :name, presence: true
  validates :code,
    presence: true,
    uniqueness: {scope: :organization_id, conditions: -> { where(deleted_at: nil) }}
  validates :currency, presence: true, inclusion: {in: currency_list}

  default_scope -> { kept }

  def self.ransackable_attributes(_auth_object = nil)
    %w[name code]
  end

  def attached_to_plan_or_subscription?
    plan_rate_cards.exists? || subscription_rate_cards.exists?
  end

  # The card bills someone once it belongs to a plan that has subscriptions or
  # is attached directly to a subscription. From that point its pricing is
  # immutable: any price change goes through a new card and a plan migration.
  def attached_to_subscriptions?
    subscription_rate_cards.exists? ||
      Subscription.where(plan_id: plan_rate_cards.select(:plan_id)).exists?
  end

  # The active rate is the latest effective rate; later rates are pending and
  # earlier ones have been superseded (terminated).
  def active_rate
    rates.effective.order(effective_datetime: :desc).first
  end

  # The rate that was active at a given time — how billing resolves the rate
  # for a period (the rate effective at the period start). Rates are
  # append-only and locked once the card has subscriptions, so only rates
  # scheduled before signing can change a subscriber's price.
  def rate_active_at(datetime)
    rates.where(effective_datetime: ..datetime).order(effective_datetime: :desc).first
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
#  proration                 :boolean          default(TRUE), not null
#  regroup_paid_fees         :enum
#  wallet_targetable         :boolean
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  organization_id           :uuid             not null
#  product_item_filter_id    :uuid
#  product_item_id           :uuid             not null
#
# Indexes
#
#  index_rate_cards_on_deleted_at                (deleted_at)
#  index_rate_cards_on_organization_id           (organization_id)
#  index_rate_cards_on_organization_id_and_code  (organization_id,code) UNIQUE WHERE (deleted_at IS NULL)
#  index_rate_cards_on_product_item_filter_id    (product_item_filter_id)
#  index_rate_cards_on_product_item_id           (product_item_id)
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (product_item_filter_id => product_item_filters.id)
#  fk_rails_...  (product_item_id => product_items.id)
#
