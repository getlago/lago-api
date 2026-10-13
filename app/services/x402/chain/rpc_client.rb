# frozen_string_literal: true

module X402
  module Chain
    class RpcClient
      DEFAULT_URLS = {
        "eip155:8453" => "https://mainnet.base.org",
        "eip155:84532" => "https://sepolia.base.org",
        "solana:5eykt4UsFv8P8NJdTREpY1vzqKqZKvdp" => "https://api.mainnet-beta.solana.com",
        "solana:EtWTRABZaYq6iMfeYKouRu166VU2xqa1" => "https://api.devnet.solana.com"
      }.freeze

      OPEN_TIMEOUT = 5
      READ_TIMEOUT = 10

      attr_reader :url

      def initialize(network:)
        @url = configured_urls.fetch(network.to_s) { raise UnreachableError, "no RPC endpoint for #{network.inspect}" }
      end

      def call(method, params)
        body = parse(method, post(method, params))
        raise UnreachableError, "#{method}: not a JSON-RPC response" unless body.is_a?(Hash)

        error = body["error"]
        raise UnreachableError, "#{method}: #{error.is_a?(Hash) ? error["message"] : "malformed error"}" if error

        if body.key?("result")
          body["result"]
        else
          raise UnreachableError, "#{method}: no result"
        end
      end

      private

      def post(method, params)
        LagoHttpClient::Client
          .new(url, open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT, retry_on_transient_errors: true)
          .post_with_response({jsonrpc: "2.0", id: 1, method:, params:}, {})
          .body.to_s
      rescue LagoHttpClient::HttpError => e
        raise UnreachableError, "#{method}: HTTP #{e.error_code}", cause: nil
      rescue => e
        raise UnreachableError, "#{method}: #{e.class}", cause: nil
      end

      def parse(method, text)
        if text.dup.force_encoding(Encoding::UTF_8).valid_encoding?
          JSON.parse(text)
        else
          raise UnreachableError, "#{method}: the answer is not valid UTF-8"
        end
      rescue JSON::ParserError
        raise UnreachableError, "#{method}: JSON::ParserError", cause: nil
      end

      def configured_urls
        raw = ENV["LAGO_X402_RPC_URLS"]
        return DEFAULT_URLS if raw.blank?

        configured = begin
          JSON.parse(raw)
        rescue JSON::ParserError
          raise UnreachableError, "LAGO_X402_RPC_URLS is not valid JSON", cause: nil
        end
        raise UnreachableError, "LAGO_X402_RPC_URLS must be a JSON object mapping a CAIP-2 network to a URL" unless configured.is_a?(Hash)

        configured.each do |network, endpoint|
          raise UnreachableError, "LAGO_X402_RPC_URLS has an invalid URL for #{named(network)}", cause: nil unless http_url?(endpoint)
        end
        DEFAULT_URLS.merge(configured)
      end

      def named(network)
        Network::NETWORKS.key?(network) ? network : "a key that is not a supported network"
      end

      def http_url?(endpoint)
        uri = URI.parse(endpoint)
        %w[http https].include?(uri.scheme) && uri.host.present?
      rescue URI::InvalidURIError, TypeError
        false
      end
    end
  end
end
