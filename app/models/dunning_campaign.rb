# frozen_string_literal: true

class DunningCampaign < ApplicationRecord
  include PaperTrailTraceable

  belongs_to :organization
  has_many :thresholds, class_name: "DunningCampaignThreshold", dependent: :destroy

  validates :name, presence: true
  validates :days_between_attempts, numericality: {greater_than: 0}
  validates :max_attempts, numericality: {greater_than: 0}
  validates :code, uniqueness: {scope: :organization_id}
end

# == Schema Information
#
# Table name: dunning_campaigns
#
#  id                      :uuid             not null, primary key
#  applied_to_organization :boolean          default(FALSE), not null
#  code                    :string           not null
#  days_between_attempts   :integer          default(1), not null
#  description             :text
#  max_attempts            :integer          default(1), not null
#  name                    :string           not null
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  organization_id         :uuid             not null
#
# Indexes
#
#  index_dunning_campaigns_on_organization_id           (organization_id)
#  index_dunning_campaigns_on_organization_id_and_code  (organization_id,code) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#
