# frozen_string_literal: true

class SubscriptionRateScheduleCycle < ApplicationRecord
  include PaperTrailTraceable

  belongs_to :organization
  belongs_to :subscription_rate_schedule

  has_many :fees, dependent: :nullify

  validates :cycle_index, presence: true, numericality: {greater_than_or_equal_to: 0}
  validates :from_datetime, presence: true
  validates :to_datetime, presence: true
end
# == Schema Information
#
# Table name: subscription_rate_schedule_cycles
# Database name: primary
#
#  id                            :uuid             not null, primary key
#  cycle_index                   :integer          not null
#  from_datetime                 :datetime         not null
#  to_datetime                   :datetime         not null
#  created_at                    :datetime         not null
#  updated_at                    :datetime         not null
#  organization_id               :uuid             not null
#  subscription_rate_schedule_id :uuid             not null
#
# Indexes
#
#  idx_srs_cycles_on_from_datetime                             (from_datetime)
#  idx_srs_cycles_on_srs_id_and_cycle_index                    (subscription_rate_schedule_id,cycle_index) UNIQUE
#  idx_srs_cycles_on_subscription_rate_schedule_id             (subscription_rate_schedule_id)
#  idx_srs_cycles_on_to_datetime                               (to_datetime)
#  index_subscription_rate_schedule_cycles_on_organization_id  (organization_id)
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (subscription_rate_schedule_id => subscription_rate_schedules.id)
#
