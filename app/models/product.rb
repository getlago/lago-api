# frozen_string_literal: true

class Product < ApplicationRecord
  include PaperTrailTraceable
  include Discard::Model
  include CatalogAttachable

  self.discard_column = :deleted_at

  PRODUCT_TYPES = {
    usage: "usage",
    fixed: "fixed"
  }.freeze

  belongs_to :organization
  belongs_to :product_category, optional: true
  belongs_to :billable_metric, -> { with_discarded }, optional: true
  belongs_to :add_on, -> { with_discarded }, optional: true
  belongs_to :charge, -> { with_discarded }, optional: true

  has_many :filters, class_name: "ProductFilter"
  has_many :rate_cards
  has_many :plan_applied_rate_cards, through: :rate_cards
  has_many :contract_applied_rate_cards, through: :rate_cards

  enum :product_type, PRODUCT_TYPES, validate: true

  validates :name, presence: true
  validates :code,
    presence: true,
    uniqueness: {scope: :organization_id, conditions: -> { where(deleted_at: nil) }}

  validate :validate_billable_metric_presence
  validate :validate_add_on_charge_exclusivity

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
      errors.add(:billable_metric, :blank)
    elsif fixed? && has_billable_metric
      errors.add(:billable_metric, :present)
    end
  end

  def validate_add_on_charge_exclusivity
    return if add_on_id.blank? || charge_id.blank?

    errors.add(:base, :add_on_and_charge_mutually_exclusive)
  end
end

# == Schema Information
#
# Table name: products
# Database name: primary
#
#  id                   :uuid             not null, primary key
#  code                 :string           not null
#  deleted_at           :datetime
#  description          :text
#  invoice_display_name :string
#  name                 :string           not null
#  product_type         :enum             not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  add_on_id            :uuid
#  billable_metric_id   :uuid
#  charge_id            :uuid
#  organization_id      :uuid             not null
#  product_category_id  :uuid
#
# Indexes
#
#  index_products_on_add_on_id                 (add_on_id)
#  index_products_on_billable_metric_id        (billable_metric_id)
#  index_products_on_charge_id                 (charge_id)
#  index_products_on_deleted_at                (deleted_at)
#  index_products_on_organization_id           (organization_id)
#  index_products_on_organization_id_and_code  (organization_id,code) UNIQUE WHERE (deleted_at IS NULL)
#  index_products_on_product_category_id       (product_category_id)
#
# Foreign Keys
#
#  fk_rails_...  (add_on_id => add_ons.id)
#  fk_rails_...  (billable_metric_id => billable_metrics.id)
#  fk_rails_...  (charge_id => charges.id)
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (product_category_id => product_categories.id)
#
