# frozen_string_literal: true

module X402
  class SignInNonce < ApplicationRecord
    belongs_to :organization

    before_validation :normalize_agent_address

    validates :agent_address, :nonce, presence: true

    private

    def normalize_agent_address
      family = X402::Network.family_of_address(agent_address)

      if family
        self.agent_address = X402::Network.normalize_address(agent_address, family:)
      end
    end
  end
end

# == Schema Information
#
# Table name: x402_sign_in_nonces
# Database name: primary
#
#  id              :uuid             not null, primary key
#  agent_address   :string           not null
#  nonce           :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  organization_id :uuid             not null
#
# Indexes
#
#  index_x402_sign_in_nonces_on_created_at                  (created_at)
#  index_x402_sign_in_nonces_on_organization_address_nonce  (organization_id,agent_address,nonce) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#
