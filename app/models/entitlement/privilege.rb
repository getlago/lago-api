# frozen_string_literal: true

module Entitlement
  class Privilege < ApplicationRecord
    include Discard::Model
    self.discard_column = :deleted_at

    default_scope -> { kept }

    VALUE_TYPES = %w[integer string boolean select].freeze

    belongs_to :organization
    belongs_to :feature, class_name: "Entitlement::Feature", foreign_key: :entitlement_feature_id

    validates :code, presence: true
    validates :value_type, presence: true, inclusion: {in: VALUE_TYPES}
  end
end

# == Schema Information
#
# Table name: entitlement_privileges
#
#  id                     :uuid             not null, primary key
#  code                   :string           not null
#  config                 :jsonb
#  deleted_at             :datetime
#  name                   :string
#  value_type             :enum             not null
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  entitlement_feature_id :uuid             not null
#  organization_id        :uuid             not null
#
# Indexes
#
#  idx_privileges_code_unique_per_feature                  (code,entitlement_feature_id) UNIQUE
#  index_entitlement_privileges_on_entitlement_feature_id  (entitlement_feature_id)
#  index_entitlement_privileges_on_organization_id         (organization_id)
#
# Foreign Keys
#
#  fk_rails_...  (entitlement_feature_id => entitlement_features.id)
#  fk_rails_...  (organization_id => organizations.id)
#
