# frozen_string_literal: true

module X402
  module SignInWithX
    module Message
      ACCOUNTS = {"eip155" => "Ethereum", "solana" => "Solana"}.freeze

      def self.build(payload)
        namespace, reference = payload["chainId"].to_s.split(":", 2)
        account = ACCOUNTS.fetch(namespace) { raise ArgumentError, "unsupported chain #{payload["chainId"]}" }

        lines = [
          "#{payload["domain"]} wants you to sign in with your #{account} account:",
          payload["address"],
          "",
          payload["statement"],
          "",
          "URI: #{payload["uri"]}",
          "Version: #{payload["version"]}",
          "Chain ID: #{reference}",
          "Nonce: #{payload["nonce"]}",
          "Issued At: #{payload["issuedAt"]}"
        ]
        lines.concat(optional_lines(payload))
        lines.join("\n")
      end

      def self.optional_lines(payload)
        lines = []
        lines << "Expiration Time: #{payload["expirationTime"]}" if payload["expirationTime"]
        lines << "Not Before: #{payload["notBefore"]}" if payload["notBefore"]
        lines << "Request ID: #{payload["requestId"]}" if payload["requestId"]
        resources = Array(payload["resources"])
        lines.push("Resources:", *resources.map { |resource| "- #{resource}" }) if resources.any?
        lines
      end

      private_class_method :optional_lines
    end
  end
end
