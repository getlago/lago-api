# frozen_string_literal: true

module UsageMonitoring
  class ContractUsageUnitsAlert < ContractAlert
    def card_value(card_usage)
      card_usage.units
    end
  end
end

# == Schema Information
#
# Table name: usage_monitoring_contract_alerts
# Database name: primary
#
#  id                   :uuid             not null, primary key
#  alert_type           :enum             not null
#  code                 :string           not null
#  deleted_at           :datetime
#  direction            :enum             default("increasing"), not null
#  last_processed_at    :datetime
#  name                 :string
#  previous_value       :decimal(30, 5)   default(0.0), not null
#  previous_windows     :jsonb            not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  contract_external_id :string           not null
#  organization_id      :uuid             not null
#  product_filter_id    :uuid
#  product_id           :uuid
#
# Indexes
#
#  idx_contract_alerts_code_unique   (organization_id,contract_external_id,code) UNIQUE WHERE (deleted_at IS NULL)
#  idx_contract_alerts_scope_unique  (organization_id,contract_external_id,alert_type,product_id,product_filter_id) UNIQUE NULLS NOT DISTINCT WHERE (deleted_at IS NULL)
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (product_filter_id => product_filters.id)
#  fk_rails_...  (product_id => products.id)
#
