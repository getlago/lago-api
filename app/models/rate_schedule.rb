# frozen_string_literal: true

class RateSchedule < ApplicationRecord
  include PaperTrailTraceable
  include Currencies
  include Discard::Model

  self.discard_column = :deleted_at

  belongs_to :organization
  belongs_to :plan_product_item, -> { with_discarded }
  belongs_to :product_item, -> { with_discarded }
  belongs_to :product_item_filter, -> { with_discarded }, optional: true

  BILLING_INTERVAL_UNITS = {day: "day", week: "week", month: "month", year: "year"}.freeze

  CHARGE_MODELS = {
    standard: "standard",
    graduated: "graduated",
    package: "package",
    percentage: "percentage",
    volume: "volume",
    graduated_percentage: "graduated_percentage",
    custom: "custom",
    dynamic: "dynamic"
  }.freeze

  REGROUP_PAID_FEES_OPTIONS = {invoice: "invoice"}.freeze

  enum :billing_interval_unit, BILLING_INTERVAL_UNITS, validate: true
  enum :charge_model, CHARGE_MODELS, validate: true
  enum :regroup_paid_fees, REGROUP_PAID_FEES_OPTIONS

  scope :pay_in_advance, -> { where(pay_in_advance: true) }

  ProductItem::ITEM_TYPES.each do |item_type|
    scope item_type, -> { joins(:product_item).where(product_item: { item_type: item_type }) }
  end

  validates :billing_interval_count, numericality: {greater_than_or_equal_to: 1}
  validates :position, presence: true
  validates :amount_currency, inclusion: {in: currency_list}

  default_scope -> { kept }
end

# == Schema Information
#
# Table name: rate_schedules
# Database name: primary
#
#  id                     :uuid             not null, primary key
#  amount_currency        :string           not null
#  applied_pricing_unit   :jsonb
#  billing_cycle_count    :integer
#  billing_interval_count :integer          not null
#  billing_interval_unit  :enum             not null
#  charge_model           :enum             not null
#  deleted_at             :datetime
#  invoice_display_name   :string
#  invoiceable            :boolean          default(TRUE), not null
#  min_amount_cents       :bigint           default(0), not null
#  pay_in_advance         :boolean          default(FALSE), not null
#  position               :integer          not null
#  properties             :jsonb            not null
#  prorated               :boolean          default(FALSE), not null
#  regroup_paid_fees      :enum
#  units                  :decimal(30, 10)
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  organization_id        :uuid             not null
#  plan_product_item_id   :uuid             not null
#  product_item_filter_id :uuid
#  product_item_id        :uuid             not null
#
# Indexes
#
#  idx_rate_schedules_on_plan_product_item_and_position  (plan_product_item_id,position) UNIQUE WHERE (deleted_at IS NULL)
#  index_rate_schedules_on_deleted_at                    (deleted_at)
#  index_rate_schedules_on_organization_id               (organization_id)
#  index_rate_schedules_on_plan_product_item_id          (plan_product_item_id)
#  index_rate_schedules_on_product_item_filter_id        (product_item_filter_id)
#  index_rate_schedules_on_product_item_id               (product_item_id)
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (plan_product_item_id => plan_product_items.id)
#  fk_rails_...  (product_item_filter_id => product_item_filters.id)
#  fk_rails_...  (product_item_id => product_items.id)
#
