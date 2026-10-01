# frozen_string_literal: true

module X402
  class Connection < ApplicationRecord
    include Discard::Model
    include SecretsStorable

    self.discard_column = :deleted_at

    FACILITATORS = {coinbase_cdp: "coinbase_cdp"}.freeze
    ASSETS = {usdc: "usdc"}.freeze
    PAYOUT_FAMILIES = {"evm" => :evm, "svm" => :svm}.freeze

    belongs_to :organization
    has_many :settlements, class_name: "X402::Settlement", foreign_key: :x402_connection_id, inverse_of: :x402_connection

    enum :facilitator, FACILITATORS, validate: true
    enum :asset, ASSETS, validate: true

    secrets_accessors :cdp_api_key_id, :cdp_api_key_secret

    before_validation :normalize_payout_addresses

    validates :code, presence: true, uniqueness: {conditions: -> { where(deleted_at: nil) }, scope: :organization_id}
    validates :name, :networks, :secrets, presence: true
    validate :validate_networks
    validate :validate_payout_addresses

    default_scope -> { kept }

    private

    def known_networks
      Array(networks).select { |network| X402::Network::NETWORKS.key?(network) }
    end

    def normalize_payout_addresses
      if payout_addresses.is_a?(Hash) && payout_addresses.key?("evm")
        self.payout_addresses = payout_addresses.merge("evm" => X402::Network.normalize_address(payout_addresses["evm"], family: :evm))
      end
    end

    def validate_networks
      if known_networks.size < Array(networks).size
        errors.add(:networks, :invalid)
      end

      if known_networks.map { |network| X402::Network.environment(network) }.uniq.size > 1
        errors.add(:networks, :mixed_environments)
      end
    end

    def validate_payout_addresses
      if payout_addresses.is_a?(Hash) && payout_addresses.keys.all? { |key| PAYOUT_FAMILIES.key?(key) }
        payout_addresses
          .filter_map { |key, address| payout_address_error(PAYOUT_FAMILIES.fetch(key), address) }
          .each { |error| errors.add(:payout_addresses, error) }
        missing_families.each { |family| errors.add(:payout_addresses, :"missing_#{family}_payout_address") }
      else
        errors.add(:payout_addresses, :invalid)
      end
    end

    def payout_address_error(family, address)
      if X402::Network.valid_address?(address, family:)
        nil
      elsif family == :evm && X402::Network::EVM_ADDRESS.match?(address.to_s)
        :invalid_checksum
      else
        :invalid_format
      end
    end

    def missing_families
      known_networks
        .map { |network| X402::Network.family_of_network(network) }
        .uniq
        .reject { |family| payout_addresses.key?(family.to_s) }
    end
  end
end

# == Schema Information
#
# Table name: x402_connections
# Database name: primary
#
#  id                    :uuid             not null, primary key
#  asset                 :enum             default("usdc"), not null
#  auto_create_customers :boolean          default(TRUE), not null
#  code                  :string           not null
#  deleted_at            :datetime
#  facilitator           :enum             default("coinbase_cdp"), not null
#  name                  :string           not null
#  networks              :string           default([]), not null, is an Array
#  payout_addresses      :jsonb            not null
#  secrets               :string           not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  organization_id       :uuid             not null
#
# Indexes
#
#  index_x402_connections_on_organization_id_and_code  (organization_id,code) UNIQUE WHERE (deleted_at IS NULL)
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#
