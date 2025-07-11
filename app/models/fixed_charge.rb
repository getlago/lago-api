# frozen_string_literal: true

# NOTE: by default invoicable is true (only option) -> create invoice along with the fixed charge.
# NOTE: all fixed charges are recurring.

class FixedCharge < ApplicationRecord
  include PaperTrailTraceable
  include Discard::Model
  self.discard_column = :deleted_at

  # NOTE: These columns were removed in the scoping phase.
  self.ignored_columns = %i[
    billing_period_duration
    billing_period_duration_unit
    trial_period
    recurring
    interval
    untis
    billing_entity_id
  ]

  belongs_to :organization
  # TODO: We create plan on organization, it will not have billing_entity....
  # and fixed charge belong to plan, so it won't have billing_entity
  # belongs_to :billing_entity
  belongs_to :add_on
  belongs_to :plan, -> { with_discarded }, touch: true
  belongs_to :parent, class_name: "FixedCharge", optional: true

  has_many :children, class_name: "FixedCharge", foreign_key: :parent_id, dependent: :nullify
  has_many :subscriptions_units_overrides, dependent: :destroy
  has_many :fees

  # TODO: applied taxes
  # has_many :applied_taxes, class_name: "FixedCharge::AppliedTax", dependent: :destroy
  # has_many :taxes, through: :applied_taxes

  CHARGE_MODELS = {
    standard: "standard",
    graduated: "graduated",
    volume: "volume"
  }

  # INTERVALS = {
  #   weekly: "weekly",
  #   monthly: "monthly",
  #   yearly: "yearly",
  #   quarterly: "quarterly"
  # }

  # PERIOD_DURATION_UNIT = {
  #   day: "day",
  #   month: "month"
  # }

  enum :charge_model, CHARGE_MODELS, default: :standard, null: false
  # enum :interval, INTERVALS, default: :monthly, null: false
  # enum :billing_period_duration_unit, PERIOD_DURATION_UNIT, default: :month, null: false

  default_scope -> { kept }

  scope :pay_in_advance, -> { where(pay_in_advance: true) }

  delegate :code, to: :add_on
# !NOTE: should not be able to have several fixed charges with the same addon for one plan
end

# == Schema Information
#
# Table name: fixed_charges
#
#  id                   :uuid             not null, primary key
#  charge_model         :enum             default("standard"), not null
#  deleted_at           :datetime
#  invoice_display_name :string
#  pay_in_advance       :boolean          default(FALSE), not null
#  properties           :jsonb            not null
#  prorated             :boolean          default(FALSE), not null
#  units                :integer          default(1)
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  add_on_id            :uuid             not null
#  organization_id      :uuid             not null
#  parent_id            :uuid
#  plan_id              :uuid             not null
#
# Indexes
#
#  index_fixed_charges_on_add_on_id        (add_on_id)
#  index_fixed_charges_on_deleted_at       (deleted_at)
#  index_fixed_charges_on_organization_id  (organization_id)
#  index_fixed_charges_on_parent_id        (parent_id)
#  index_fixed_charges_on_plan_id          (plan_id)
#
# Foreign Keys
#
#  fk_rails_...  (add_on_id => add_ons.id)
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (plan_id => plans.id)
#
