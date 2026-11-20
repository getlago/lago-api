# frozen_string_literal: true

module UsageMonitoring
  class ContractActivity < ApplicationRecord
    belongs_to :organization
    belongs_to :contract
  end
end

# == Schema Information
#
# Table name: usage_monitoring_contract_activities
# Database name: primary
#
#  id              :bigint           not null, primary key
#  enqueued        :boolean          default(FALSE), not null
#  enqueued_at     :datetime
#  inserted_at     :datetime         not null
#  contract_id     :uuid             not null
#  organization_id :uuid             not null
#
# Indexes
#
#  idx_contract_activities_enqueued_per_org  (organization_id,enqueued)
#  idx_contract_activity_unique              (contract_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (contract_id => contracts.id)
#  fk_rails_...  (organization_id => organizations.id)
#
