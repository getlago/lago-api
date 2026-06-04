# frozen_string_literal: true

class ProductItem < ApplicationRecord
  include PaperTrailTraceable
  include Discard::Model

  self.discard_column = :deleted_at

  ITEM_TYPES = {
    usage: "usage",
    fixed: "fixed"
  }.freeze

  belongs_to :organization
  belongs_to :product, optional: true
  belongs_to :billable_metric, -> { with_discarded }, optional: true
  belongs_to :add_on, -> { with_discarded }, optional: true
  belongs_to :charge, -> { with_discarded }, optional: true

  has_many :filters, class_name: "ProductItemFilter"
  has_many :rate_cards
  has_many :plan_product_items

  enum :item_type, ITEM_TYPES, validate: true

  validates :name, presence: true
  validates :code, presence: true

  validate :validate_billable_metric_presence
  validate :validate_add_on_charge_exclusivity
  validate :validate_code_unique

  default_scope -> { kept }

  def self.ransackable_attributes(_auth_object = nil)
    %w[name code]
  end

  def invoice_name
    invoice_display_name.presence || name
  end

  private

  def validate_billable_metric_presence
    has_billable_metric = billable_metric_id.present? || billable_metric.present?

    if usage? && !has_billable_metric
      errors.add(:billable_metric_id, :blank)
    elsif fixed? && has_billable_metric
      errors.add(:billable_metric_id, :present)
    end
  end

  def validate_add_on_charge_exclusivity
    return if add_on_id.blank? || charge_id.blank?

    errors.add(:base, :add_on_and_charge_mutually_exclusive)
  end

  def validate_code_unique
    return if code.blank?

    scope = self.class.where(code:, deleted_at: nil).where.not(id:)
    scope = if product_id.present?
      scope.where(product_id:)
    else
      scope.where(organization_id:, product_id: nil)
    end

    errors.add(:code, :taken) if scope.exists?
  end
end

# == Schema Information
#
# Table name: product_items
# Database name: primary
#
#  id                   :uuid             not null, primary key
#  code                 :string           not null
#  deleted_at           :datetime
#  description          :text
#  invoice_display_name :string
#  item_type            :enum             not null
#  name                 :string           not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  add_on_id            :uuid
#  billable_metric_id   :uuid
#  charge_id            :uuid
#  organization_id      :uuid             not null
#  product_id           :uuid
#
# Indexes
#
#  index_product_items_on_add_on_id                            (add_on_id)
#  index_product_items_on_billable_metric_id                   (billable_metric_id)
#  index_product_items_on_charge_id                            (charge_id)
#  index_product_items_on_deleted_at                           (deleted_at)
#  index_product_items_on_organization_id                      (organization_id)
#  index_product_items_on_product_id                           (product_id)
#  index_product_items_on_product_id_and_code                  (product_id,code) UNIQUE WHERE ((product_id IS NOT NULL) AND (deleted_at IS NULL))
#  index_standalone_product_items_on_organization_id_and_code  (organization_id,code) UNIQUE WHERE ((product_id IS NULL) AND (deleted_at IS NULL))
#
# Foreign Keys
#
#  fk_rails_...  (add_on_id => add_ons.id)
#  fk_rails_...  (billable_metric_id => billable_metrics.id)
#  fk_rails_...  (charge_id => charges.id)
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (product_id => products.id)
#
