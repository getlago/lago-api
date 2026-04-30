# frozen_string_literal: true

class ProductItemFilter < ApplicationRecord
  include PaperTrailTraceable
  include Discard::Model

  self.discard_column = :deleted_at

  belongs_to :organization
  belongs_to :product_item, -> { with_discarded }
  belongs_to :billable_metric_filter, -> { with_discarded }

  has_many :values, class_name: "ProductItemFilterValue", dependent: :destroy

  validates :billable_metric_filter_id,
    uniqueness: {conditions: -> { where(deleted_at: nil) }, scope: :product_item_id}

  default_scope -> { kept }
end

# == Schema Information
#
# Table name: product_item_filters
# Database name: primary
#
#  id                        :uuid             not null, primary key
#  deleted_at                :datetime
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  billable_metric_filter_id :uuid             not null
#  organization_id           :uuid             not null
#  product_item_id           :uuid             not null
#
# Indexes
#
#  idx_product_item_filters_on_item_and_bm_filter           (product_item_id,billable_metric_filter_id) UNIQUE WHERE (deleted_at IS NULL)
#  index_product_item_filters_on_billable_metric_filter_id  (billable_metric_filter_id)
#  index_product_item_filters_on_deleted_at                 (deleted_at)
#  index_product_item_filters_on_organization_id            (organization_id)
#  index_product_item_filters_on_product_item_id            (product_item_id)
#
# Foreign Keys
#
#  fk_rails_...  (billable_metric_filter_id => billable_metric_filters.id)
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (product_item_id => product_items.id)
#
