# frozen_string_literal: true

class SubscriptionFeatureEntitlementRemoval < ApplicationRecord
  belongs_to :organization
  belongs_to :feature
end

# == Schema Information
#
# Table name: subscription_feature_entitlement_removals
#
#  id                       :uuid             not null, primary key
#  deleted_at               :datetime
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  feature_id               :uuid             not null
#  organization_id          :uuid             not null
#  subscription_external_id :string           not null
#
# Indexes
#
#  idx_on_organization_id_7c0d40612b                              (organization_id)
#  idx_on_subscription_external_id_f9eccd2bac                     (subscription_external_id)
#  idx_on_subscription_external_id_feature_id_0780bec906          (subscription_external_id,feature_id) UNIQUE WHERE (deleted_at IS NULL)
#  index_subscription_feature_entitlement_removals_on_feature_id  (feature_id)
#
# Foreign Keys
#
#  fk_rails_...  (feature_id => features.id)
#  fk_rails_...  (organization_id => organizations.id)
#
