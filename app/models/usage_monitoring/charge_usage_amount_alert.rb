# frozen_string_literal: true

module UsageMonitoring
  class ChargeUsageAmountAlert < Alert
    def find_value(thing_that_has_values_in_it)
      thing_that_has_values_in_it.fees.find { |fee| fee.charge_id == charge_id }.amount_cents
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
