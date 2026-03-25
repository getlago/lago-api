# frozen_string_literal: true

class ProductItem < ApplicationRecord
  include PaperTrailTraceable
  include Discard::Model

  self.discard_column = :deleted_at

  belongs_to :organization
  belongs_to :product, -> { with_discarded }
  belongs_to :billable_metric, -> { with_discarded }, optional: true
  belongs_to :add_on, -> { with_discarded }, optional: true
  belongs_to :charge, -> { with_discarded }, optional: true

  has_many :filters, dependent: :destroy, class_name: "ProductItemFilter"

  ITEM_TYPES = {usage: "usage", fixed: "fixed", subscription: "subscription"}.freeze

  enum :item_type, ITEM_TYPES, validate: true

  validates :code, presence: true,
    uniqueness: {conditions: -> { where(deleted_at: nil) }, scope: :product_id}

  validate :validate_billable_metric_presence
  validate :validate_subscription_type_constraints
  validate :validate_one_subscription_item_per_product

  default_scope -> { kept }

  private

  def validate_billable_metric_presence
    if usage? && billable_metric_id.nil?
      errors.add(:billable_metric, :required_for_usage_type)
    end

    if (fixed? || subscription?) && billable_metric_id.present?
      errors.add(:billable_metric, :must_be_nil_for_non_usage_type)
    end
  end

  def validate_subscription_type_constraints
    return unless subscription?

    errors.add(:add_on, :must_be_nil_for_subscription_type) if add_on_id.present?
    errors.add(:charge, :must_be_nil_for_subscription_type) if charge_id.present?
  end

  def validate_one_subscription_item_per_product
    return unless subscription?

    scope = self.class.where(product_id:, item_type: :subscription)
    scope = scope.where.not(id:) if persisted?
    errors.add(:item_type, :only_one_subscription_per_product) if scope.exists?
  end
end

# == Schema Information
#
# Table name: product_items
# Database name: primary
#
#  id                    :uuid             not null, primary key
#  accepts_target_wallet :boolean
#  code                  :string           not null
#  deleted_at            :datetime
#  description           :text
#  grouping_key          :string
#  invoice_display_name  :string
#  item_type             :enum             not null
#  name                  :string
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  add_on_id             :uuid
#  billable_metric_id    :uuid
#  charge_id             :uuid
#  organization_id       :uuid             not null
#  product_id            :uuid             not null
#
# Indexes
#
#  index_product_items_on_add_on_id            (add_on_id)
#  index_product_items_on_billable_metric_id   (billable_metric_id)
#  index_product_items_on_charge_id            (charge_id)
#  index_product_items_on_deleted_at           (deleted_at)
#  index_product_items_on_organization_id      (organization_id)
#  index_product_items_on_product_id           (product_id)
#  index_product_items_on_product_id_and_code  (product_id,code) UNIQUE WHERE (deleted_at IS NULL)
#
# Foreign Keys
#
#  fk_rails_...  (add_on_id => add_ons.id)
#  fk_rails_...  (billable_metric_id => billable_metrics.id)
#  fk_rails_...  (charge_id => charges.id)
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (product_id => products.id)
#
