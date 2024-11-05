# frozen_string_literal: true

class ApiKey < ApplicationRecord
  include PaperTrailTraceable

  belongs_to :organization

  before_create :set_value

  validates :value, uniqueness: true
  validates :value, presence: true, on: :update

  scope :active, -> { where('expires_at IS NULL OR expires_at > ?', Time.current) }

  private

  def set_value
    loop do
      self.value = SecureRandom.uuid
      break unless self.class.exists?(value:)
    end
  end
end

# == Schema Information
#
# Table name: api_keys
#
#  id              :uuid             not null, primary key
#  expires_at      :datetime
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
