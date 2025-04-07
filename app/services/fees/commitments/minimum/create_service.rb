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

          currency = invoice.total_amount.currency
          precise_unit_amount = true_up_fee_result.amount_cents / currency.subunit_to_unit.to_f

          new_fee = Fee.new(
            invoice:,
            organization_id: organization.id,
            billing_entity_id: invoice.billing_entity_id,
            subscription:,
            fee_type: :commitment,
            invoiceable_type: "Commitment",
            invoiceable_id: minimum_commitment.id,
            amount_cents: true_up_fee_result.amount_cents,
            precise_amount_cents: true_up_fee_result.precise_amount_cents,
            unit_amount_cents: true_up_fee_result.amount_cents,
            amount_currency: subscription.plan.amount_currency,
            invoice_display_name: minimum_commitment.invoice_name,
            units: 1,
            precise_unit_amount:,
            taxes_amount_cents: 0
          )

          new_fee.save!
          result.fee = new_fee

          result
        rescue ActiveRecord::RecordInvalid => e
          result.record_validation_failure!(record: e.record)
        end

        private

        attr_reader :minimum_commitment, :invoice_subscription

        delegate :invoice, :subscription, to: :invoice_subscription
        delegate :organization, to: :invoice

        def invoice_has_minimum_commitment_fee?
          invoice.fees.commitment.where(subscription:).any? { |fee| fee.invoiceable.minimum_commitment? }
        end
      end
    end
  end
end
