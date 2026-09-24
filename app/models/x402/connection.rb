# frozen_string_literal: true

module X402
  # D1: the merchant's facilitator credentials, payout addresses and network menu. Nothing commercial (D13).
  class Connection < ApplicationRecord
    include Discard::Model
    include SecretsStorable

    self.discard_column = :deleted_at

    ASSETS = {usdc: "usdc"}.freeze

    belongs_to :organization
    has_many :settlements, class_name: "X402::Settlement", foreign_key: :x402_connection_id, inverse_of: :x402_connection

    enum :asset, ASSETS, validate: true

    secrets_accessors :cdp_api_key_id, :cdp_api_key_secret

    validates :code, :name, :networks, presence: true

    default_scope -> { kept }

    # D14: payout addresses are keyed by chain family, not by network.
    def payout_address_for(network)
      payout_addresses[X402::Network.family_of_network(network).to_s]
    end
  end
end

# == Schema Information
#
# Table name: x402_connections
# Database name: primary
#
#  id               :uuid             not null, primary key
#  asset            :enum             default("usdc"), not null
#  code             :string           not null
#  deleted_at       :datetime
#  name             :string           not null
#  networks         :string           default([]), not null, is an Array
#  payout_addresses :jsonb            not null
#  secrets          :string
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  organization_id  :uuid             not null
#
# Indexes
#
#  index_x402_connections_on_organization_id           (organization_id)
#  index_x402_connections_on_organization_id_and_code  (organization_id,code) UNIQUE WHERE (deleted_at IS NULL)
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#
