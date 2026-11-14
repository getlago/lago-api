# frozen_string_literal: true

module Agents
  class Registration < ApplicationRecord
    self.table_name = "agent_registrations"

    STATUSES = {active: "active", revoked: "revoked"}.freeze

    belongs_to :organization
    belongs_to :storefront, class_name: "Integrations::AgentStorefrontIntegration", foreign_key: :integration_id

    enum :status, STATUSES, validate: true

    attr_readonly :key_id, :public_key

    validates :key_id, :public_key, presence: true
  end
end

# == Schema Information
#
# Table name: agent_registrations
# Database name: primary
#
#  id                    :uuid             not null, primary key
#  last_authenticated_at :datetime
#  public_key            :string           not null
#  revoked_at            :datetime
#  status                :enum             default("active"), not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  integration_id        :uuid             not null
#  key_id                :string           not null
#  organization_id       :uuid             not null
#
# Indexes
#
#  index_agent_registrations_on_integration_id_and_key_id  (integration_id,key_id) UNIQUE
#  index_agent_registrations_on_organization_id            (organization_id)
#
# Foreign Keys
#
#  fk_rails_...  (integration_id => integrations.id)
#  fk_rails_...  (organization_id => organizations.id)
#
