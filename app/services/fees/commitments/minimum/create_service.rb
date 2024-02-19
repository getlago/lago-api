# frozen_string_literal: true

module Fees
  module Commitments
    module Minimum
      class CreateService < BaseService
        def initialize(invoice_subscription:)
          @invoice_subscription = invoice_subscription
          @minimum_commitment = invoice_subscription.subscription.plan.minimum_commitment

          super
        end

        def call
          return result if invoice_has_minimum_commitment_fee? || !minimum_commitment

          true_up_fee_result = ::Commitments::Minimum::CalculateTrueUpFeeService
            .new_instance(invoice_subscription:).call

          new_fee = Fee.new(
            invoice:,
            subscription:,
            fee_type: :commitment,
            invoiceable_type: 'Commitment',
            invoiceable_id: minimum_commitment.id,
            amount_cents: true_up_fee_result.amount_cents,
            amount_currency: subscription.plan.amount_currency,
            taxes_amount_cents: 0,
          )

          taxes_result = Fees::ApplyTaxesService.call(fee: new_fee)
          taxes_result.raise_if_error!

          new_fee.save!
          result.fee = new_fee

          result
        rescue ActiveRecord::RecordInvalid => e
          result.record_validation_failure!(record: e.record)
        end

        private

        attr_reader :minimum_commitment, :invoice_subscription

        delegate :invoice, :subscription, to: :invoice_subscription

        def invoice_has_minimum_commitment_fee?
          invoice.fees.commitment_kind.where(subscription:).any? { |fee| fee.invoiceable.minimum_commitment? }
        end
      end
    end
  end
end
