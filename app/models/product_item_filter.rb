# frozen_string_literal: true

class ProductItemFilter < ApplicationRecord
  include PaperTrailTraceable
  include Discard::Model

  self.discard_column = :deleted_at

  belongs_to :organization
  belongs_to :product_item

  validates :name, presence: true
  validates :code,
    presence: true,
    uniqueness: {scope: :product_item_id, conditions: -> { where(deleted_at: nil) }}

  default_scope -> { kept.order(updated_at: :asc) }

  def self.ransackable_attributes(_auth_object = nil)
    %w[name code]
  end

  def invoice_name
    invoice_display_name.presence || name
  end
end

# == Schema Information
#
# Table name: product_item_filters
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
#  product_item_id      :uuid             not null
#
# Indexes
#
#  index_product_item_filters_on_deleted_at                (deleted_at)
#  index_product_item_filters_on_organization_id           (organization_id)
#  index_product_item_filters_on_product_item_id           (product_item_id)
#  index_product_item_filters_on_product_item_id_and_code  (product_item_id,code) UNIQUE WHERE (deleted_at IS NULL)
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (product_item_id => product_items.id)
#
