# frozen_string_literal: true

module Wallets
  module Balance
    class CalculateApplicableFeesService < BaseService
      Result = BaseResult[:applicable_fees, :total_amount_cents]

      def initialize(wallet:, invoice:)
        @wallet = wallet
        @invoice = invoice
        super
      end

      def call
        result.applicable_fees = applicable_fees
        result.total_amount_cents = capped_total_amount_cents
        result
      end

      private

      attr_reader :wallet, :invoice

      def capped_total_amount_cents
        return invoice.total_amount_cents unless wallet.limited_fee_types? || wallet.limited_to_billable_metrics?

        [precise_total_amount_cents, invoice.total_amount_cents].min
      end

      def precise_total_amount_cents
        applicable_fees.sum do |fee|
          fee.sub_total_excluding_taxes_precise_amount_cents +
            fee.taxes_precise_amount_cents -
            fee.precise_credit_notes_amount_cents
        end
      end

      def applicable_fees
        @applicable_fees ||= begin
          billable_metric_fees, other_fees = partition_fees_by_billable_metric
          billable_metric_fees + filter_fees_by_type(other_fees)
        end
      end

      def fees
        invoice.fees
      end

      def partition_fees_by_billable_metric
        return [[], fees.to_a] unless wallet.limited_to_billable_metrics?

        matching_fees = fees
          .joins(charge: :billable_metric)
          .where(billable_metrics: {id: limited_billable_metric_ids})

        non_charge_fees = (fees - matching_fees).reject(&:charge?)
        [matching_fees, non_charge_fees]
      end

      def limited_billable_metric_ids
        @limited_billable_metric_ids ||= wallet.wallet_targets.map(&:billable_metric_id)
      end

      def filter_fees_by_type(other_fees)
        return other_fees.select { |fee| wallet.allowed_fee_types.include?(fee.fee_type) } if wallet.limited_fee_types?
        return [] if wallet.limited_to_billable_metrics?

        other_fees
      end
    end
  end
end
