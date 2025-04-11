# frozen_string_literal: true

class Subscription
  class UsageActivity < ApplicationRecord
    self.table_name = "subscription_usage_activities"

    belongs_to :organization
    belongs_to :subscription
  end
end

# == Schema Information
#
# Table name: subscription_usage_activities
#
#  id                        :uuid             not null, primary key
#  recalculate_current_usage :boolean          default(FALSE), not null
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  organization_id           :uuid             not null
#  subscription_id           :uuid             not null
#
# Indexes
#
#  index_subscription_usage_activities_on_organization_id  (organization_id)
#  index_subscription_usage_activities_on_subscription_id  (subscription_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (subscription_id => subscriptions.id)
#
