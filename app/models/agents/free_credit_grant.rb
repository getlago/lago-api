# frozen_string_literal: true

module Agents
  # The free credits a storefront's plan offers, collected once per owner mailbox at that storefront. The unique index
  # on the storefront and the mailbox digest is the once-only guard.
  class FreeCreditGrant < ApplicationRecord
    self.table_name = "agent_free_credit_grants"

    UNIQUE_INDEX = "index_agent_free_credit_grants_on_integration_and_email_hash"

    belongs_to :organization
    belongs_to :storefront, class_name: "Integrations::AgentStorefrontIntegration", foreign_key: :integration_id
    belongs_to :registration, class_name: "Agents::Registration"
    belongs_to :wallet_transaction, optional: true

    validates :email_hash, :amount_cents, presence: true
  end
end

# == Schema Information
#
# Table name: agent_free_credit_grants
# Database name: primary
#
#  id                    :uuid             not null, primary key
#  amount_cents          :bigint           not null
#  email_hash            :string           not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  integration_id        :uuid             not null
#  organization_id       :uuid             not null
#  registration_id       :uuid             not null
#  wallet_transaction_id :uuid
#
# Indexes
#
#  index_agent_free_credit_grants_on_integration_and_email_hash  (integration_id,email_hash) UNIQUE
#  index_agent_free_credit_grants_on_organization_id             (organization_id)
#  index_agent_free_credit_grants_on_registration_id             (registration_id)
#  index_agent_free_credit_grants_on_wallet_transaction_id       (wallet_transaction_id)
#
# Foreign Keys
#
#  fk_rails_...  (integration_id => integrations.id)
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (registration_id => agent_registrations.id) ON DELETE => cascade
#  fk_rails_...  (wallet_transaction_id => wallet_transactions.id)
#
