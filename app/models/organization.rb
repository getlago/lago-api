# frozen_string_literal: true

class Organization < ApplicationRecord
  has_many :memberships
  has_many :users, through: :memberships
  has_many :billable_metrics
  has_many :products

  before_create :generate_api_key

  validates_presence_of :name

  private

  def generate_api_key
    api_key = SecureRandom.uuid
    orga = Organization.find_by(api_key: api_key)

    return generate_api_key if orga.present?

    self.api_key = SecureRandom.uuid
  end
end
