# frozen_string_literal: true

module X402
  class SignInNonce < ApplicationRecord
    belongs_to :organization

    validates :agent_address, :nonce, presence: true
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
