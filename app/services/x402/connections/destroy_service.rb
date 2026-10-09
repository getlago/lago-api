# frozen_string_literal: true

module X402
  module Connections
    class DestroyService < BaseService
      Result = BaseResult[:connection]

      def initialize(connection:)
        @connection = connection
        super
      end

      def call
        return result.not_found_failure!(resource: "x402_connection") unless connection

        connection.discard!

        register_security_log

        result.connection = connection
        result
      end

      private

      attr_reader :connection

      delegate :organization, to: :connection

      def register_security_log
        Utils::SecurityLog.produce(
          organization:,
          log_type: "integration",
          log_event: "integration.deleted",
          resources: {integration_name: connection.name, integration_type: "x402"}
        )
      end
    end
  end
end
