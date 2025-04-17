# frozen_string_literal: true

module UsageMonitoring
  class SubscriptionActivity < ApplicationRecord
    belongs_to :organization
    belongs_to :subscription
  end
end

# == Schema Information
#
# Table name: usage_monitoring_subscription_activities
#
#  id              :uuid             not null, primary key
#  at              :datetime         not null
#  organization_id :uuid             not null
#  subscription_id :uuid             not null
#
# Indexes
#
#  idx_on_organization_id_376a587b04  (organization_id)
#  idx_subscription_unique            (subscription_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (subscription_id => subscriptions.id)
#
