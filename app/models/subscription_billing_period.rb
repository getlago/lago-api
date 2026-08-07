# frozen_string_literal: true

# Persisted charge-period boundaries per subscription, maintained ahead of
# time (current + next period) by Clock::RefreshSubscriptionBillingPeriodsJob.
#
# Consumed via CDC by the realtime usage pipeline (extra/risingwave) so that
# event-driven aggregation can be keyed by billing period while the date
# logic stays in Ruby (Subscriptions::DatesService).
class SubscriptionBillingPeriod < ApplicationRecord
  belongs_to :organization
  belongs_to :subscription

  validates :charges_from, :charges_to, presence: true

  scope :covering, ->(time) { where("charges_from <= ? AND charges_to >= ?", time, time) }
end

# == Schema Information
#
# Table name: subscription_billing_periods
# Database name: primary
#
#  id              :uuid             not null, primary key
#  charges_from    :datetime         not null
#  charges_to      :datetime         not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  organization_id :uuid             not null
#  subscription_id :uuid             not null
#
# Indexes
#
#  idx_on_subscription_id_charges_from_61b8f07abf         (subscription_id,charges_from) UNIQUE
#  index_subscription_billing_periods_on_organization_id  (organization_id)
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (subscription_id => subscriptions.id)
#
