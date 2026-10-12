# frozen_string_literal: true

module X402
  module Settlements
    class ReconcileService < BaseService
      Result = BaseResult[:settlement]
      READERS = {evm: X402::Chain::EvmReader, svm: X402::Chain::SvmReader}.freeze
      TRANSACTION_INDEX = "index_x402_settlements_on_network_and_transaction_hash"

      def initialize(settlement:)
        @settlement = settlement

        super
      end

      def call
        raise "#{self.class.name} must run outside a database transaction" if in_transaction?

        reconcile if settlement.pending?

        result.settlement = settlement
        result
      end

      private

      attr_reader :settlement

      def reconcile
        if reader.settled?
          mark_settled(reader.identifier)
        elsif reader.final?
          transition(status: :failed)
        end
      rescue X402::Chain::Error => e
        report(e)
      end

      def reader
        @reader ||= READERS.fetch(X402::Network.family_of_network(settlement.network)).new(
          network: settlement.network,
          payment: settlement.payload["payment"],
          payment_requirements: settlement.payload["payment_requirements"],
          since: settlement.created_at
        )
      end

      def mark_settled(transaction_hash)
        transition(status: :settled, transaction_hash:)
      rescue ActiveRecord::RecordNotUnique => e
        raise unless e.message.include?(TRANSACTION_INDEX)

        settlement.restore_attributes
        transition(status: :failed, error_reason: "transaction_already_recorded")
      end

      def transition(**attributes)
        settlement.with_lock do
          settlement.update!(**attributes) if settlement.pending?
        end
      end

      def report(error)
        Rails.logger.warn("[x402] chain read failed settlement_id=#{settlement.id} network=#{settlement.network}: #{error.class} #{error.message}")
        Sentry.capture_exception(error, extra: {organization_id: settlement.organization_id, settlement_id: settlement.id, network: settlement.network})
      end
    end
  end
end
