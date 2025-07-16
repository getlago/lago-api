# frozen_string_literal: true

class FixedCharge < ApplicationRecord
  belongs_to :organization
  belongs_to :plan
  belongs_to :add_on
  belongs_to :parent, optional: true

  CHARGE_MODELS = {
    standard: "standard",
    graduated: "graduated",
    volume: "volume"
  }.freeze

  enum :charge_model, CHARGE_MODELS

  validates :units, numericality: {greater_than_or_equal_to: 0}
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
