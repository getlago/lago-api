# frozen_string_literal: true

module X402
  module Facilitator
    class Client
      def self.for(connection)
        case connection.facilitator
        when "coinbase_cdp"
          X402::Facilitator::CoinbaseCdpAdapter.new(api_key_id: connection.cdp_api_key_id, api_key_secret: connection.cdp_api_key_secret)
        else
          raise NotImplementedError, "x402 facilitator #{connection.facilitator.inspect} is not supported"
        end
      end
    end
  end
end
