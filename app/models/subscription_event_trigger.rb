# frozen_string_literal: true

class SubscriptionEventTrigger < ApplicationRecord
  validates :organization_id, :external_subscription_id, :created_at, presence: true

  scope :ordered, -> { order(created_at: :desc) }

  def self.trigger(organization_id:, external_subscription_id:)
    connection.select_all sanitize_sql_array(["call trigger_subscription_update(?,?, null)", organization_id, external_subscription_id])
  end

  def self.take
    candidate = SubscriptionEventTrigger.ordered.limit(1)
  end
end

# == Schema Information
#
# Table name: subscription_event_triggers
#
#  id                       :uuid             not null, primary key
#  start_processing_at      :datetime
#  created_at               :datetime         not null
#  external_subscription_id :string           not null
#  organization_id          :uuid             not null
#
# Indexes
#
#  idx_on_external_subscription_id_organization_id_40aa74e2eb      (external_subscription_id,organization_id) UNIQUE WHERE (start_processing_at IS NULL)
#  idx_on_start_processing_at_external_subscription_id_31b81116ce  (start_processing_at,external_subscription_id,organization_id) UNIQUE
#
