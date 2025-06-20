# frozen_string_literal: true

class Privilege < ApplicationRecord
  belongs_to :organization
  belongs_to :feature
end

# == Schema Information
#
# Table name: privileges
#
#  id              :uuid             not null, primary key
#  code            :string           not null
#  deleted_at      :datetime
#  name            :string
#  value_type      :string           default("string"), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  feature_id      :uuid             not null
#  organization_id :uuid             not null
#
# Indexes
#
#  index_privileges_on_feature_id           (feature_id)
#  index_privileges_on_feature_id_and_code  (feature_id,code) UNIQUE WHERE (deleted_at IS NULL)
#  index_privileges_on_organization_id      (organization_id)
#
# Foreign Keys
#
#  fk_rails_...  (feature_id => features.id)
#  fk_rails_...  (organization_id => organizations.id)
#
