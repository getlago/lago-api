# frozen_string_literal: true

class ProductFilter < ApplicationRecord
  include PaperTrailTraceable
  include Discard::Model

  self.discard_column = :deleted_at

  belongs_to :organization
  belongs_to :product

  has_many :values, class_name: "ProductFilterValue"
  has_many :billable_metric_filters, through: :values
  has_many :rate_cards

  delegate :attached_to_plan_or_subscription?, to: :product

  def attached_to_subscriptions?
    ContractRateCard.joins(:rate_card).where(rate_cards: {product_filter_id: id}).exists?
  end

  validates :name, presence: true
  validates :code,
    presence: true,
    uniqueness: {scope: :product_id, conditions: -> { where(deleted_at: nil) }}

  default_scope -> { kept.order(created_at: :asc) }

  def self.ransackable_attributes(_auth_object = nil)
    %w[name code]
  end

  def invoice_name
    invoice_display_name.presence || name
  end

  def to_h
    @to_h ||= values.each_with_object({}) do |filter_value, result|
      (result[filter_value.billable_metric_filter.key] ||= []) << filter_value.value
    end.freeze
  end
end

# == Schema Information
#
# Table name: product_filters
# Database name: primary
#
#  id                   :uuid             not null, primary key
#  code                 :string           not null
#  deleted_at           :datetime
#  description          :string
#  invoice_display_name :string
#  name                 :string           not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  organization_id      :uuid             not null
#  product_id           :uuid             not null
#
# Indexes
#
#  index_product_filters_on_deleted_at           (deleted_at)
#  index_product_filters_on_organization_id      (organization_id)
#  index_product_filters_on_product_id           (product_id)
#  index_product_filters_on_product_id_and_code  (product_id,code) UNIQUE WHERE (deleted_at IS NULL)
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (product_id => products.id)
#
