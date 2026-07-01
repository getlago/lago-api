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

  PRORATIONS = {
    full: "full",
    none: "none"
  }.freeze

  REGROUP_PAID_FEES = {
    invoice: "invoice"
  }.freeze

  belongs_to :organization
  belongs_to :product_item
  belongs_to :product_item_filter, optional: true

  has_many :rates, class_name: "RateCardRate"
  has_many :plan_product_items

  enum :billing_timing, BILLING_TIMINGS, validate: true
  enum :proration, PRORATIONS, validate: true, prefix: true
  enum :regroup_paid_fees, REGROUP_PAID_FEES, validate: {allow_nil: true}

  validates :name, presence: true
  validates :code,
    presence: true,
    uniqueness: {scope: [:product_item_id, :product_item_filter_id], conditions: -> { where(deleted_at: nil) }}
  validates :currency, presence: true, inclusion: {in: currency_list}

  default_scope -> { kept }

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
#  proration                 :enum             default("full"), not null
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
#  index_filterless_rate_cards_on_product_item_id_and_code  (product_item_id,code) UNIQUE WHERE ((product_item_filter_id IS NULL) AND (deleted_at IS NULL))
#  index_rate_cards_on_deleted_at                           (deleted_at)
#  index_rate_cards_on_item_filter_and_code                 (product_item_id,product_item_filter_id,code) UNIQUE WHERE (deleted_at IS NULL)
#  index_rate_cards_on_organization_id                      (organization_id)
#  index_rate_cards_on_product_item_filter_id               (product_item_filter_id)
#  index_rate_cards_on_product_item_id                      (product_item_id)
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (product_item_filter_id => product_item_filters.id)
#  fk_rails_...  (product_item_id => product_items.id)
#
