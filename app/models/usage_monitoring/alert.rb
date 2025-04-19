# frozen_string_literal: true

module UsageMonitoring
  class Alert < ApplicationRecord
    include Discard::Model

    self.discard_column = :deleted_at
    self.inheritance_column = :alert_type

    STI_MAPPING = {
      "usage_amount" => "UsageMonitoring::UsageAmountAlert",
      "charge_usage_amount" => "UsageMonitoring::ChargeUsageAmountAlert"
    }

    CURRENT_USAGE_TYPES = %w[usage_amount charge_usage_amount]

    belongs_to :organization
    belongs_to :charge, optional: true

    has_many :thresholds,
      foreign_key: :usage_monitoring_alert_id,
      class_name: "UsageMonitoring::AlertThreshold",
      dependent: :delete_all

    has_many :triggered_alerts,
      foreign_key: :usage_monitoring_alert_id,
      class_name: "UsageMonitoring::TriggeredAlert"

    # QUESTION: todo only one with active.first?
    # Question: Should we store the actual primary key and migrate alerts when we have upgrade/downgrade ?
    # has_many :subscription,
    #   primary_key: :subscription_external_id,
    #   foreign_key: :external_id,
    #   class_name: "Subscription"

    def self.find_sti_class(type_name)
      STI_MAPPING.fetch(type_name).constantize
    end

    def self.sti_name
      STI_MAPPING.invert.fetch(name)
    end

    def subscription
      # What if we stored the customer_id in the Alert table :think:
      # customer.subscriptions instead of organization.subscriptions
      @subscription ||= organization
        .subscriptions
        .active
        .order(started_at: :desc)
        .find_by(external_id: subscription_external_id)
    end

    # TODO: Better name?

    def find_thresholds_crossed(current)
      # TODO: optimize this for the beauty of it
      thresholds_values.filter { |t| t.between?(previous_value, current) }
    end

    def thresholds_values
      thresholds.all.pluck(:value).uniq.sort
    end

    def formatted_crossed_thresholds(crossed_threshold_values)
      thresholds
        .filter { crossed_threshold_values.include?(_1.value) }
        .map { |t| {code: t.code, value: t.value} }
    end
  end
end

# == Schema Information
#
# Table name: usage_monitoring_alerts
#
#  id                       :uuid             not null, primary key
#  alert_type               :string           not null
#  code                     :string
#  deleted_at               :datetime
#  last_processed_at        :datetime
#  previous_value           :decimal(30, 5)   default(0.0), not null
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  charge_id                :uuid
#  organization_id          :uuid             not null
#  subscription_external_id :string           not null
#
# Indexes
#
#  idx_alerts_unique_per_type_per_customer                    (subscription_external_id,organization_id,alert_type) UNIQUE WHERE ((charge_id IS NULL) AND (deleted_at IS NULL))
#  idx_alerts_unique_per_type_per_customer_with_charge        (subscription_external_id,organization_id,alert_type,charge_id) UNIQUE WHERE ((charge_id IS NOT NULL) AND (deleted_at IS NULL))
#  index_usage_monitoring_alerts_on_charge_id                 (charge_id)
#  index_usage_monitoring_alerts_on_organization_id           (organization_id)
#  index_usage_monitoring_alerts_on_subscription_external_id  (subscription_external_id)
#
# Foreign Keys
#
#  fk_rails_...  (charge_id => charges.id)
#  fk_rails_...  (organization_id => organizations.id)
#
