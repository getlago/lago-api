# frozen_string_literal: true

class ProductItemFilterValue < ApplicationRecord
  include PaperTrailTraceable
  include Discard::Model

  self.discard_column = :deleted_at

  belongs_to :organization
  belongs_to :product_item_filter, -> { with_discarded }

  validates :value, presence: true,
    uniqueness: {conditions: -> { where(deleted_at: nil) }, scope: :product_item_filter_id}
  validate :validate_value_inclusion

  default_scope -> { kept }

  private

  def validate_value_inclusion
    return if value.blank?
    return if product_item_filter&.billable_metric_filter&.values&.include?(value)

    errors.add(:value, :inclusion)
  end
end

# == Schema Information
#
# Table name: product_item_filter_values
# Database name: primary
#
#  id                     :uuid             not null, primary key
#  deleted_at             :datetime
#  value                  :string           not null
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  organization_id        :uuid             not null
#  product_item_filter_id :uuid             not null
#
# Indexes
#
#  idx_product_item_filter_values_on_filter_and_value          (product_item_filter_id,value) UNIQUE WHERE (deleted_at IS NULL)
#  index_product_item_filter_values_on_deleted_at              (deleted_at)
#  index_product_item_filter_values_on_organization_id         (organization_id)
#  index_product_item_filter_values_on_product_item_filter_id  (product_item_filter_id)
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (product_item_filter_id => product_item_filters.id)
#
