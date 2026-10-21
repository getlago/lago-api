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

        if settlement.pending?
          reconcile
        elsif unpaid?
          finish_payment(settlement.transaction_hash)
        end
        grant if ungranted?

        result.settlement = settlement
        result
      end

      private

      attr_reader :settlement

      def reconcile
        if reader.settled?
          mark_settled(reader.identifier)
        elsif reader.final?
          transition(status: :failed, transaction_hash: nil) { fail_invoice if settlement.invoice_payment? }
        end
      rescue X402::Chain::Error => e
        report("chain read failed", e)
      end

      def ungranted?
        settlement.credit_purchase? && settlement.settled? && settlement.wallet_transaction_id.nil?
      end

      def grant
        grant_result = X402::CreditPurchases::GrantService.call(settlement:)
        report("credit grant failed", grant_result.error) if grant_result.failure?
      rescue => e
        settlement.reload

        if settlement.wallet_transaction_id.nil?
          report("credit grant failed", e)
        else
          report("credit grant follow-up failed", e)
        end
      end

      def unpaid?
        settlement.invoice_payment? && settlement.settled? && settlement.payment_id.nil? && settlement.error_reason != "payment_not_recorded"
      end

      def finish_payment(transaction_hash)
        X402::Invoices::FinishPaymentService.call(settlement:, transaction_hash:)
      end

      def fail_invoice
        invoice = settlement.invoice.lock!

        if invoice.finalized? && invoice.payment_pending?
          ::Invoices::UpdateService.call!(invoice:, params: {payment_status: "failed"}, webhook_notification: true)
        end
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
        if settlement.invoice_payment?
          finish_payment(transaction_hash)
        else
          transition(status: :settled, transaction_hash:)
        end
      rescue ActiveRecord::RecordNotUnique => e
        raise unless e.message.include?(TRANSACTION_INDEX)

        settlement.restore_attributes
        resolve_conflict(X402::Settlement.find_by(network: settlement.network, transaction_hash:))
      end

      def resolve_conflict(holder)
        if holder&.settled?
          Rails.logger.warn("[x402] transaction already recorded settlement_id=#{settlement.id} holder_id=#{holder.id} network=#{settlement.network}")
          transition(status: :failed, transaction_hash: nil, error_reason: "transaction_already_recorded")
        elsif holder&.failed?
          report_held_transaction(holder)
        end
      end

      def transition(**attributes)
        settlement.with_lock do
          if settlement.pending?
            settlement.update!(**attributes)
            yield if block_given?
          end
        end
      end

      def report(failure, error)
        Rails.logger.warn("[x402] #{failure} settlement_id=#{settlement.id} network=#{settlement.network}: #{error.class} #{error.message}")
        Sentry.capture_exception(error, extra: {organization_id: settlement.organization_id, settlement_id: settlement.id, network: settlement.network})
      end

      def report_held_transaction(holder)
        message = "[x402] transaction held by a failed settlement"

        Rails.logger.warn("#{message} settlement_id=#{settlement.id} holder_id=#{holder.id} network=#{settlement.network}")
        Sentry.capture_message(message, extra: {organization_id: settlement.organization_id, settlement_id: settlement.id, holder_id: holder.id, network: settlement.network})
      end
    end
  end
end
