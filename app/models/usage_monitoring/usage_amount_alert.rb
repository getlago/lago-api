# frozen_string_literal: true

module UsageMonitoring
  class UsageAmountAlert < Alert
    def formatted_thresholds
      thresholds.pluck(:value).map(&:to_i).sort
    end

    def find_thresholds_crossed(current)
      formatted_thresholds.filter { |t| t.between?(previous_value, current) }
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
#  previous_value           :decimal(30, 5)   default(0.0), not null
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  billable_metric_id       :uuid
#  organization_id          :uuid             not null
#  subscription_external_id :string           not null
#
# Indexes
#
#  index_alerts_unique_per_type_per_customer                  (subscription_external_id,organization_id,alert_type) UNIQUE WHERE ((billable_metric_id IS NULL) AND (deleted_at IS NULL))
#  index_alerts_unique_per_type_per_customer_with_bm          (subscription_external_id,organization_id,alert_type,billable_metric_id) UNIQUE WHERE ((billable_metric_id IS NOT NULL) AND (deleted_at IS NULL))
#  index_usage_monitoring_alerts_on_billable_metric_id        (billable_metric_id)
#  index_usage_monitoring_alerts_on_organization_id           (organization_id)
#  index_usage_monitoring_alerts_on_subscription_external_id  (subscription_external_id)
#
# Foreign Keys
#
#  fk_rails_...  (billable_metric_id => billable_metrics.id)
#  fk_rails_...  (organization_id => organizations.id)
#
