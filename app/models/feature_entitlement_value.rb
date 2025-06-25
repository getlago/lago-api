# frozen_string_literal: true

class FeatureEntitlementValue < ApplicationRecord
  include Discard::Model
  self.discard_column = :deleted_at

  belongs_to :organization
  belongs_to :feature_entitlement
  belongs_to :privilege

  default_scope -> { kept }
end

# == Schema Information
#
# Table name: feature_entitlement_values
#
#  id                     :uuid             not null, primary key
#  deleted_at             :datetime
#  value                  :string           not null
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  feature_entitlement_id :uuid             not null
#  organization_id        :uuid             not null
#  privilege_id           :uuid             not null
#
# Indexes
#
#  idx_on_privilege_id_feature_entitlement_id_1e0b74b1a6       (privilege_id,feature_entitlement_id) WHERE (deleted_at IS NULL)
#  index_feature_entitlement_values_on_feature_entitlement_id  (feature_entitlement_id)
#  index_feature_entitlement_values_on_organization_id         (organization_id)
#  index_feature_entitlement_values_on_privilege_id            (privilege_id)
#
# Foreign Keys
#
#  fk_rails_...  (feature_entitlement_id => feature_entitlements.id)
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (privilege_id => privileges.id)
#
