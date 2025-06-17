# frozen_string_literal: true

class FixedCharge < ApplicationRecord
  include PaperTrailTraceable
  include Discard::Model
  self.discard_column = :deleted_at

  belongs_to :organization
  belongs_to :billing_entity
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
  }

  INTERVALS = {
    weekly: "weekly",
    monthly: "monthly",
    yearly: "yearly",
    quarterly: "quarterly"
  }

  PERIOD_DURATION_UNIT = {
    day: "day",
    month: "month"
  }

  enum :charge_model, CHARGE_MODELS, default: :standard, null: false
  enum :interval, INTERVALS, default: :monthly, null: false
  enum :billing_period_duration_unit, PERIOD_DURATION_UNIT, default: :month, null: false

  default_scope -> { kept }

  scope :pay_in_advance, -> { where(pay_in_advance: true) }
end

# == Schema Information
#
# Table name: fixed_charges
#
#  id                           :uuid             not null, primary key
#  billing_period_duration      :integer
#  billing_period_duration_unit :enum             default("month"), not null
#  charge_model                 :enum             default("standard"), not null
#  deleted_at                   :datetime
#  interval                     :enum             default("monthly"), not null
#  invoice_display_name         :string
#  pay_in_advance               :boolean          default(FALSE), not null
#  properties                   :jsonb            not null
#  prorated                     :boolean          default(FALSE), not null
#  recurring                    :boolean          default(TRUE), not null
#  trial_period                 :integer          default(0), not null
#  untis                        :integer          default(0), not null
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#  add_on_id                    :uuid             not null
#  billing_entity_id            :uuid             not null
#  organization_id              :uuid             not null
#  parent_id                    :uuid
#  plan_id                      :uuid             not null
#
# Indexes
#
#  index_fixed_charges_on_add_on_id          (add_on_id)
#  index_fixed_charges_on_billing_entity_id  (billing_entity_id)
#  index_fixed_charges_on_deleted_at         (deleted_at)
#  index_fixed_charges_on_organization_id    (organization_id)
#  index_fixed_charges_on_parent_id          (parent_id)
#  index_fixed_charges_on_plan_id            (plan_id)
#
# Foreign Keys
#
#  fk_rails_...  (add_on_id => add_ons.id)
#  fk_rails_...  (billing_entity_id => billing_entities.id)
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (plan_id => plans.id)
#
