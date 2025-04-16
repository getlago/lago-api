# frozen_string_literal: true

module UsageMonitoring
  class UsageAmountAlert < Alert
    def formatted_thresholds
      thresholds.pluck(:value).map(&:to_i).sort
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
