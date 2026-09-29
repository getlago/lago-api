# frozen_string_literal: true

module X402
  module ExternalIds
    def self.customer(address, family:)
      "x402_#{normalized(address, family:)}"
    end

    def self.subscription(address, plan_code, family:)
      "x402_#{normalized(address, family:)}_#{plan_code}"
    end

    def self.normalized(address, family:)
      raise ArgumentError, "invalid #{family} address: #{address.inspect}" unless Network.valid_address?(address, family:)

      Network.normalize_address(address, family:)
    end
    private_class_method :normalized
  end
end
