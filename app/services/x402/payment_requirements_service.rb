# frozen_string_literal: true

module X402
  class PaymentRequirementsService < BaseService
    Result = BaseResult[:requirements]

    def initialize(connection:, amount_cents:)
      @connection = connection
      @amount_cents = amount_cents

      super
    end

    def call
      result.requirements = connection.networks.map { |network| requirement(network) }
      result
    rescue X402::Facilitator::Error => e
      reason = e.class.name.demodulize.underscore
      result.third_party_failure!(third_party: connection.facilitator, error_code: reason, error_message: "#{reason}: #{e.message}")
    end

    private

    attr_reader :connection, :amount_cents

    def requirement(network)
      asset = X402::Asset.fetch(code: connection.asset, network:)
      family = X402::Network.family_of_network(network)

      {
        scheme: X402::PaymentPayload::SCHEME,
        network:,
        asset: connection.asset,
        asset_address: asset.address,
        extra: (family == :svm) ? {"feePayer" => fee_payer(network)} : asset.eip712_domain,
        pay_to: connection.payout_addresses.fetch(family.to_s),
        amount_atomic: asset.atomic_from_cents(amount_cents).to_s,
        max_timeout_seconds: X402::PaymentPayload::MAX_TIMEOUT_SECONDS
      }
    end

    def fee_payer(network)
      fee_payer = supported.fee_payer(network:)

      if X402::Network.valid_address?(fee_payer, family: :svm)
        fee_payer
      else
        raise X402::Facilitator::UnavailableError, "supported: no valid fee payer for #{network}"
      end
    end

    def supported
      @supported ||= X402::Facilitator::Client.for(connection).supported
    end
  end
end
