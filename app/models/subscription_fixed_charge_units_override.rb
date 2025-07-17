# frozen_string_literal: true

class SubscriptionFixedChargeUnitsOverride < ApplicationRecord
  include Discard::Model
  include PaperTrailTraceable
  self.discard_column = :deleted_at
  default_scope -> { kept }

  belongs_to :organization
  belongs_to :billing_entity
  belongs_to :subscription
  belongs_to :fixed_charge

  validates :units, numericality: {greater_than_or_equal_to: 0}
end

# == Schema Information
#
# Table name: subscription_fixed_charge_units_overrides
#
#  id                :uuid             not null, primary key
#  deleted_at        :datetime
#  units             :decimal(30, 10)  default(0.0), not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  billing_entity_id :uuid             not null
#  fixed_charge_id   :uuid             not null
#  organization_id   :uuid             not null
#  subscription_id   :uuid             not null
#
# Indexes
#
#  idx_on_billing_entity_id_ba78f5f5a5                            (billing_entity_id)
#  idx_on_fixed_charge_id_06503ae1a5                              (fixed_charge_id)
#  idx_on_organization_id_e742f77454                              (organization_id)
#  idx_on_subscription_id_bd763c5aa3                              (subscription_id)
#  idx_on_subscription_id_fixed_charge_id_d85b30a9bf              (subscription_id,fixed_charge_id) UNIQUE WHERE (deleted_at IS NULL)
#  index_subscription_fixed_charge_units_overrides_on_deleted_at  (deleted_at)
#
# Foreign Keys
#
#  fk_rails_...  (billing_entity_id => billing_entities.id)
#  fk_rails_...  (fixed_charge_id => fixed_charges.id)
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (subscription_id => subscriptions.id)
#
