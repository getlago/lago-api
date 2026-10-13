# frozen_string_literal: true

module LagoHttpClient
  class BlockedAddressError < StandardError
    def initialize(host)
      super("Destination address is not allowed: #{host}")
    end
  end
end
