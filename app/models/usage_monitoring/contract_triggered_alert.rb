# frozen_string_literal: true

module UsageMonitoring
  class ContractTriggeredAlert < ApplicationRecord
    include TriggeredAlertRecord

    belongs_to :organization
    belongs_to :contract
    belongs_to :alert,
      -> { with_discarded },
      foreign_key: :contract_alert_id,
      class_name: "UsageMonitoring::ContractAlert"

    def alertable=(alertable)
      case alertable
      when Contract then self.contract = alertable
      else raise ArgumentError, "unsupported alertable: #{alertable.class}"
      end
    end
  end
end

# == Schema Information
#
# Table name: usage_monitoring_contract_triggered_alerts
# Database name: primary
#
#  id                  :uuid             not null, primary key
#  crossed_thresholds  :jsonb            not null
#  current_value       :decimal(30, 5)   not null
#  fully_resolved      :boolean
#  in_alarm_thresholds :jsonb
#  kind                :enum             default("triggered"), not null
#  previous_value      :decimal(30, 5)   not null
#  resolution_reason   :enum
#  triggered_at        :datetime         not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  contract_alert_id   :uuid             not null
#  contract_id         :uuid             not null
#  organization_id     :uuid             not null
#
# Indexes
#
#  idx_on_contract_alert_id_57bb7b1808  (contract_alert_id)
#  idx_on_organization_id_018fe27a33    (organization_id)
#
# Foreign Keys
#
#  fk_rails_...  (contract_alert_id => usage_monitoring_contract_alerts.id)
#  fk_rails_...  (contract_id => contracts.id)
#  fk_rails_...  (organization_id => organizations.id)
#
