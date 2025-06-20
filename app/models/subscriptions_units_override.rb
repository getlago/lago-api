# frozen_string_literal: true

class SubscriptionsUnitsOverride < ApplicationRecord
  belongs_to :subscription
  belongs_to :fixed_charge
  belongs_to :organization

  # should this belongs to a billing entity?

  validates :units, presence: true
end

# == Schema Information
#
# Table name: subscriptions_units_overrides
#
#  id              :uuid             not null, primary key
#  units           :decimal(30, 10)  not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  charge_id       :uuid
#  fixed_charge_id :uuid
#  organization_id :uuid
#  subscription_id :uuid             not null
#
# Indexes
#
#  idx_on_subscription_id_fixed_charge_id_charge_id_b3bf74a0d0  (subscription_id,fixed_charge_id,charge_id) UNIQUE
#  index_subscriptions_units_overrides_on_charge_id             (charge_id)
#  index_subscriptions_units_overrides_on_fixed_charge_id       (fixed_charge_id)
#  index_subscriptions_units_overrides_on_organization_id       (organization_id)
#  index_subscriptions_units_overrides_on_subscription_id       (subscription_id)
#
# Foreign Keys
#
#  fk_rails_...  (charge_id => charges.id)
#  fk_rails_...  (fixed_charge_id => fixed_charges.id)
#  fk_rails_...  (subscription_id => subscriptions.id)
#
