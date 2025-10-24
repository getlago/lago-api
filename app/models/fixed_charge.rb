# frozen_string_literal: true

class FixedCharge < ApplicationRecord
  include PaperTrailTraceable
  include ChargePropertiesValidation
  include Discard::Model

  self.discard_column = :deleted_at
  default_scope -> { kept }

  belongs_to :organization
  belongs_to :plan, -> { with_discarded }, touch: true
  belongs_to :add_on, -> { with_discarded }, touch: true
  belongs_to :parent, class_name: "FixedCharge", optional: true
  has_many :children, class_name: "FixedCharge", foreign_key: :parent_id, dependent: :nullify
  has_many :applied_taxes, class_name: "FixedCharge::AppliedTax", dependent: :destroy
  has_many :taxes, through: :applied_taxes
  has_many :fees
  has_many :events, class_name: "FixedChargeEvent", dependent: :destroy

  has_many :applied_taxes, class_name: "FixedCharge::AppliedTax", dependent: :destroy
  has_many :taxes, through: :applied_taxes

  scope :pay_in_advance, -> { where(pay_in_advance: true) }

  CHARGE_MODELS = {
    standard: "standard",
    graduated: "graduated",
    volume: "volume"
  }.freeze

  enum :charge_model, CHARGE_MODELS
  delegate :code, to: :add_on

  validates :units, numericality: {greater_than_or_equal_to: 0}
  validates :charge_model, presence: true
  validates :pay_in_advance, inclusion: {in: [true, false]}
  validates :prorated, inclusion: {in: [true, false]}
  validates :properties, presence: true

  validate :validate_properties

  def equal_properties?(fixed_charge)
    charge_model == fixed_charge.charge_model && properties == fixed_charge.properties
  end

  private

  def validate_properties
    return if properties.blank?

    validate_charge_model_properties(charge_model)
  end
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
#  units                :decimal(30, 10)  default(0.0), not null
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
