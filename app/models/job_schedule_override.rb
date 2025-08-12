# frozen_string_literal: true

class JobScheduleOverride < ApplicationRecord
  include Discard::Model
  self.discard_column = :deleted_at

  belongs_to :organization

  validates :job_name, presence: true, uniqueness: {scope: :organization_id}
  validates :frequency_secods, numericality: {only_integer: true, greater_than: 0}

  default_scope -> { kept }
  scope :enabled, -> { where.not(enabled_at: nil) }
end

# == Schema Information
#
# Table name: job_schedule_overrides
#
#  id               :uuid             not null, primary key
#  deleted_at       :datetime
#  enabled_at       :datetime
#  frequency_secods :integer
#  job_name         :string
#  last_enqueued_at :datetime
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  organization_id  :uuid             not null
#
# Indexes
#
#  index_job_schedule_overrides_on_organization_id               (organization_id)
#  index_job_schedule_overrides_on_organization_id_and_job_name  (organization_id,job_name) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#
