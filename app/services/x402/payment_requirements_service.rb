# frozen_string_literal: true

module X402
  # D12: a challenge asks for a top-up of a caller-supplied amount and never prices a call. One entry per configured
  # network, in Lago-native fields (D7): the middleware renders them into the 402 of the agent's x402 version.
  class PaymentRequirementsService < BaseService
    MAX_TIMEOUT_SECONDS = 60

    Result = BaseResult[:requirements]

    def initialize(connection:, amount_cents:)
      @connection = connection
      @amount_cents = amount_cents
      super
    end

    def call
      result.requirements = connection.networks.map do |network|
        asset = X402::Asset.fetch(code: connection.asset, network:)

        {
          scheme: "exact",
          network:,
          asset: connection.asset,
          pay_to: connection.payout_address_for(network),
          amount_atomic: (amount_cents * asset.atomic_units_per_cent).to_s,
          max_timeout_seconds: MAX_TIMEOUT_SECONDS
        }
      end

      result
    end

    private

    attr_reader :connection, :amount_cents
  end
end
