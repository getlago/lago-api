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

  REGROUP_PAID_FEES = {
    invoice: "invoice"
  }.freeze

  belongs_to :organization
  belongs_to :product
  belongs_to :product_filter, optional: true

  has_many :rates, class_name: "RateCardRate"
  has_many :plan_applied_rate_cards, class_name: "PlanRateCard"
  has_many :subscription_applied_rate_cards, class_name: "SubscriptionRateCard"

  enum :billing_timing, BILLING_TIMINGS, validate: true
  enum :regroup_paid_fees, REGROUP_PAID_FEES, validate: {allow_nil: true}

  validates :name, presence: true
  validates :code,
    presence: true,
    uniqueness: {scope: :organization_id, conditions: -> { where(deleted_at: nil) }}
  # allow_nil keeps a missing currency on the presence error only; the
  # inclusion error fires for a provided-but-unknown currency.
  validates :currency, presence: true, inclusion: {in: currency_list, allow_nil: true}
  validate :validate_filter_belongs_to_item

  default_scope -> { kept }

  # A card scoped to a filter must price a slice of its own item.
  def validate_filter_belongs_to_item
    return if product_filter.nil?
    return if product_filter.product_id == product_id

    errors.add(:product_filter, :does_not_belong_to_product)
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[name code]
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
#  regroup_paid_fees         :enum
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
