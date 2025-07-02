# frozen_string_literal: true

module Entitlement
  class Entitlement < ApplicationRecord
    include Discard::Model
    self.discard_column = :deleted_at

    default_scope -> { kept }

    belongs_to :organization
    belongs_to :feature, class_name: "Entitlement::Feature", foreign_key: :entitlement_feature_id
    belongs_to :plan

    has_many :values, class_name: "Entitlement::EntitlementValue", foreign_key: :entitlement_entitlement_id, dependent: :destroy

    validates :entitlement_feature_id, presence: true
    validates :plan_id, presence: true
  end
end

# == Schema Information
#
# Table name: entitlement_entitlements
#
#  id                     :uuid             not null, primary key
#  deleted_at             :datetime
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  entitlement_feature_id :uuid             not null
#  organization_id        :uuid             not null
#  plan_id                :uuid             not null
#
# Indexes
#
#  idx_on_entitlement_feature_id_plan_id_c45949ea26          (entitlement_feature_id,plan_id) UNIQUE WHERE (deleted_at IS NULL)
#  index_entitlement_entitlements_on_entitlement_feature_id  (entitlement_feature_id)
#  index_entitlement_entitlements_on_organization_id         (organization_id)
#  index_entitlement_entitlements_on_plan_id                 (plan_id)
#
# Foreign Keys
#
#  fk_rails_...  (entitlement_feature_id => entitlement_features.id)
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (plan_id => plans.id)
#
