# frozen_string_literal: true

class ApiKey < ApplicationRecord
  include PaperTrailTraceable

  belongs_to :organization

  before_create :set_value

  def generate_value
    value = SecureRandom.uuid
    api_key = ApiKey.find_by(value:)

    return generate_value if api_key.present?

    value
  end

  private

  def set_value
    self.value = generate_value
  end
end

# == Schema Information
#
# Table name: api_keys
#
#  id              :uuid             not null, primary key
#  value           :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  organization_id :uuid             not null
#
# Indexes
#
#  index_api_keys_on_organization_id  (organization_id)
#  index_api_keys_on_value            (value) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#
