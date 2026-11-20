# frozen_string_literal: true

module UsageMonitoring
  class ContractAlertThreshold < ApplicationRecord
    include ThresholdRecord

    belongs_to :organization
    belongs_to :alert,
      foreign_key: :contract_alert_id,
      class_name: "UsageMonitoring::ContractAlert"
  end
end

# == Schema Information
#
# Table name: usage_monitoring_contract_alert_thresholds
# Database name: primary
#
#  id                :uuid             not null, primary key
#  code              :string
#  notify_on         :string           default(["triggered"]), not null, is an Array
#  recurring         :boolean          default(FALSE), not null
#  value             :decimal(30, 5)   not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  contract_alert_id :uuid             not null
#  organization_id   :uuid             not null
#
# Indexes
#
#  idx_on_contract_alert_id_b9d4b2ca0c            (contract_alert_id)
#  idx_on_contract_alert_id_recurring_fd386586d1  (contract_alert_id,recurring) UNIQUE WHERE (recurring IS TRUE)
#  idx_on_organization_id_902d09b6f8              (organization_id)
#
# Foreign Keys
#
#  fk_rails_...  (contract_alert_id => usage_monitoring_contract_alerts.id)
#  fk_rails_...  (organization_id => organizations.id)
#
