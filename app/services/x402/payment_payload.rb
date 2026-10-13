# frozen_string_literal: true

module X402
  class PaymentPayload
    X402_VERSION = 2
    SCHEME = "exact"
    MAX_TIMEOUT_SECONDS = 60

    attr_reader :payment, :payment_requirements

    def initialize(payment:, payment_requirements:)
      @payment = payment
      @payment_requirements = payment_requirements
    end

    def x402_version
      payment_data["x402Version"]
    end

    def scheme
      requirements_data["scheme"]
    end

    def network
      requirements_data["network"]
    end

    def asset
      requirements_data["asset"]
    end

    def pay_to
      requirements_data["payTo"]
    end

    def amount
      X402::UnsignedInteger.parse(requirements_data["amount"])
    end

    def max_timeout_seconds
      timeout = requirements_data["maxTimeoutSeconds"]

      if timeout.is_a?(Integer)
        timeout
      end
    end

    def family
      if X402::Network::NETWORKS.key?(network)
        X402::Network.family_of_network(network)
      end
    end

    def authorization
      @authorization ||= hash_or_empty(payload_data["authorization"])
    end

    def from
      authorization["from"]
    end

    def to
      authorization["to"]
    end

    def value
      X402::UnsignedInteger.parse(authorization["value"])
    end

    def valid_before
      X402::UnsignedInteger.parse(authorization["validBefore"])
    end

    def transaction
      payload_data["transaction"]
    end

    private

    def payment_data
      @payment_data ||= hash_or_empty(payment)
    end

    def requirements_data
      @requirements_data ||= hash_or_empty(payment_requirements)
    end

    def payload_data
      @payload_data ||= hash_or_empty(payment_data["payload"])
    end

    def hash_or_empty(value)
      value.is_a?(Hash) ? value.deep_stringify_keys : {}
    end
  end
end
