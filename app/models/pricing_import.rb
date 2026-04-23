# frozen_string_literal: true

class PricingImport < ApplicationRecord
  STATES = {
    draft: "draft",
    confirmed: "confirmed",
    processing: "processing",
    completed: "completed",
    failed: "failed"
  }.freeze

  belongs_to :organization
  belongs_to :membership, optional: true
  has_one :user, through: :membership

  enum :state, STATES, validate: true

  validates :source_filename, presence: true

  def processing!
    update!(state: "processing", started_at: Time.current)
  end

  def complete!
    update!(state: "completed", finished_at: Time.current)
  end

  def fail!(message)
    update!(state: "failed", error_message: message, finished_at: Time.current)
  end
end

# == Schema Information
#
# Table name: pricing_imports
# Database name: primary
#
#  id               :uuid             not null, primary key
#  edited_plan      :jsonb            not null
#  error_message    :text
#  execution_report :jsonb            not null
#  finished_at      :datetime
#  progress_current :integer          default(0), not null
#  progress_total   :integer          default(0), not null
#  proposed_plan    :jsonb            not null
#  source_filename  :string
#  started_at       :datetime
#  state            :enum             default("draft"), not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  membership_id    :uuid
#  organization_id  :uuid             not null
#
# Indexes
#
#  index_pricing_imports_on_membership_id    (membership_id)
#  index_pricing_imports_on_organization_id  (organization_id)
#
# Foreign Keys
#
#  fk_rails_...  (membership_id => memberships.id)
#  fk_rails_...  (organization_id => organizations.id)
#
