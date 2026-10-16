# frozen_string_literal: true

module X402
  module Invoices
    class FinishPaymentService < BaseService
      Result = BaseResult[:settlement, :payment]

      def initialize(settlement:, transaction_hash:)
        @settlement = settlement
        @transaction_hash = transaction_hash

        super
      end

      def call
        raise "#{self.class.name} must run outside a database transaction" if in_transaction?

        ActiveRecord::Base.transaction do
          settlement.lock!
          settlement.update!(status: :settled, transaction_hash:) if settlement.pending?
          record_payment if settlement.settled? && settlement.payment_id.nil?
        end

        result.settlement = settlement
        result
      end

      private

      attr_reader :settlement, :transaction_hash

      def record_payment
        payment_result = X402::Payments::CreateService.call(settlement:, invoice: settlement.invoice)

        if payment_result.success?
          result.payment = payment_result.payment
        else
          report(payment_result.error)
        end
      end

      def report(error)
        Rails.logger.warn("#{self.class.name} call failed reason=payment_failed settlement_id=#{settlement.id} network=#{settlement.network}: #{error.message}")
        Sentry.capture_exception(error, extra: {organization_id: settlement.organization_id, settlement_id: settlement.id, network: settlement.network})
      end
    end
  end
end
