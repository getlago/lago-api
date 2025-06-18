# frozen_string_literal: true

class Feature < ApplicationRecord
  belongs_to :organization
  has_many :privileges, dependent: :destroy
end

# == Schema Information
#
# Table name: features
#
#  id              :uuid             not null, primary key
#  code            :string           not null
#  deleted_at      :datetime
#  description     :text
#  name            :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  organization_id :uuid             not null
#
# Indexes
#
#  index_features_on_organization_id           (organization_id)
#  index_features_on_organization_id_and_code  (organization_id,code) UNIQUE WHERE (deleted_at IS NULL)
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#
