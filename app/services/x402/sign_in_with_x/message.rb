# frozen_string_literal: true

module X402
  module SignInWithX
    module Message
      ACCOUNTS = {"eip155" => "Ethereum", "solana" => "Solana"}.freeze

      def self.build(payload, empty_statement_line: true)
        namespace, reference = payload["chainId"].to_s.split(":", 2)
        account = ACCOUNTS.fetch(namespace) { raise ArgumentError, "unsupported chain #{payload["chainId"]}" }

        lines = [
          "#{payload["domain"]} wants you to sign in with your #{account} account:",
          payload["address"],
          "",
          *statement_lines(payload["statement"], empty_statement_line),
          "URI: #{payload["uri"]}",
          "Version: #{payload["version"]}",
          "Chain ID: #{reference}",
          "Nonce: #{payload["nonce"]}",
          "Issued At: #{payload["issuedAt"]}"
        ]
        lines.concat(optional_lines(payload))
        lines.join("\n")
      end

      def self.statement_lines(statement, empty_statement_line)
        if statement
          [statement, ""]
        elsif empty_statement_line
          [""]
        else
          []
        end
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

      private_class_method :statement_lines, :optional_lines
    end
  end
end
