# frozen_string_literal: true

module UsageMonitoring
  class Alert < ApplicationRecord
    include Discard::Model

    self.discard_column = :deleted_at
    self.inheritance_column = :alert_type

    STI_MAPPING = {
      "usage_amount" => "UsageMonitoring::UsageAmountAlert"
    }

    belongs_to :organization
    belongs_to :plan, optional: true
    belongs_to :billable_metric, optional: true

    has_many :thresholds,
      primary_key: :id,
      foreign_key: :usage_monitoring_alerts_id,
      class_name: "UsageMonitoring::AlertThreshold"

    # QUESTION: todo only one with active.first?
    # has_many :subscription,
    #   primary_key: :subscription_external_id,
    #   foreign_key: :external_id,
    #   class_name: "Subscription"

    validate :validate_plan_or_subscription_exclusivity

    def self.find_sti_class(type_name)
      STI_MAPPING.fetch(type_name).constantize
    end

    def self.sti_name
      STI_MAPPING.invert.fetch(name)
    end

    def current_value
      raise NotImplementedError
    end

    private

    def validate_plan_or_subscription_exclusivity
      if plan_id.blank? && subscription_external_id.blank?
        errors.add(:base, "Either plan_id or subscription_external_id must be present.")
      elsif plan_id.present? && subscription_external_id.present?
        errors.add(:base, "Only one of plan_id or subscription_external_id can be present.")
      end
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
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  billable_metric_id       :uuid
#  organization_id          :uuid             not null
#  plan_id                  :uuid
#  subscription_external_id :string
#
# Indexes
#
#  index_usage_monitoring_alerts_on_billable_metric_id        (billable_metric_id)
#  index_usage_monitoring_alerts_on_organization_id           (organization_id)
#  index_usage_monitoring_alerts_on_plan_id                   (plan_id)
#  index_usage_monitoring_alerts_on_subscription_external_id  (subscription_external_id)
#
# Foreign Keys
#
#  fk_rails_...  (billable_metric_id => billable_metrics.id)
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (plan_id => plans.id)
#
