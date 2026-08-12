# frozen_string_literal: true

class ProductFilterValue < ApplicationRecord
  include PaperTrailTraceable
  include Discard::Model

  self.discard_column = :deleted_at

  belongs_to :organization
  belongs_to :product_filter, -> { with_discarded }
  belongs_to :billable_metric_filter, -> { with_discarded }

  # A NULL value selects the key alone: the filter matches any event carrying
  # the key. An empty string is still invalid — absence is expressed by nil.
  validates :value, presence: true, allow_nil: true
  validates :value,
    uniqueness: {scope: [:product_filter_id, :billable_metric_filter_id], conditions: -> { where(deleted_at: nil) }}
  validate :validate_value_inclusion

  default_scope -> { kept.order(created_at: :asc) }

  delegate :key, to: :billable_metric_filter

  private

  def validate_value_inclusion
    return if value.blank?
    return if billable_metric_filter&.values&.include?(value) # rubocop:disable Performance/InefficientHashSearch

    errors.add(:value, :inclusion)
  end
end

# == Schema Information
#
# Table name: product_filter_values
# Database name: primary
#
#  id                        :uuid             not null, primary key
#  deleted_at                :datetime
#  value                     :string
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  billable_metric_filter_id :uuid             not null
#  organization_id           :uuid             not null
#  product_filter_id         :uuid             not null
#
# Indexes
#
#  idx_pif_values_on_filter_metric_filter_and_value          (product_filter_id,billable_metric_filter_id,value) UNIQUE NULLS NOT DISTINCT WHERE (deleted_at IS NULL)
#  index_product_filter_values_on_billable_metric_filter_id  (billable_metric_filter_id)
#  index_product_filter_values_on_deleted_at                 (deleted_at)
#  index_product_filter_values_on_organization_id            (organization_id)
#  index_product_filter_values_on_product_filter_id          (product_filter_id)
#
# Foreign Keys
#
#  fk_rails_...  (billable_metric_filter_id => billable_metric_filters.id)
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (product_filter_id => product_filters.id)
#
