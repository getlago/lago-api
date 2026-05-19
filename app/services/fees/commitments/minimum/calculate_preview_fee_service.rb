# frozen_string_literal: true

module Fees
  module Commitments
    module Minimum
      class CalculatePreviewFeeService < BaseService
        Result = BaseResult[:fee]

        def initialize(invoice_subscription:, preview_fees_amount_cents:, preview_fees_precise_amount_cents:)
          @invoice_subscription = invoice_subscription
          @preview_fees_amount_cents = preview_fees_amount_cents
          @preview_fees_precise_amount_cents = preview_fees_precise_amount_cents
          @minimum_commitment = invoice_subscription.subscription.plan.minimum_commitment

          super
        end

        def call
          return result unless minimum_commitment
          return result if pay_in_advance_first_period?

          true_up_amount_cents = [commitment_amount_cents - fees_total_amount_cents, 0].max
          return result if true_up_amount_cents.zero?

          true_up_precise_amount_cents = [commitment_amount_cents - fees_total_precise_amount_cents, 0].max
          precise_unit_amount = true_up_amount_cents / currency.subunit_to_unit.to_f

          new_fee = Fee.new(
            invoice:,
            organization_id: organization.id,
            billing_entity_id: invoice.billing_entity_id,
            subscription:,
            fee_type: :commitment,
            invoiceable_type: "Commitment",
            invoiceable_id: minimum_commitment.id,
            amount_cents: true_up_amount_cents,
            precise_amount_cents: true_up_precise_amount_cents,
            unit_amount_cents: true_up_amount_cents,
            precise_unit_amount:,
            amount_currency: subscription.plan.amount_currency,
            invoice_display_name: minimum_commitment.invoice_name,
            units: 1,
            taxes_amount_cents: 0,
            taxes_precise_amount_cents: 0.to_d,
            properties: commitment_boundaries
          )

          result.fee = new_fee
          result
        end

        private

        attr_reader :invoice_subscription, :minimum_commitment,
          :preview_fees_amount_cents, :preview_fees_precise_amount_cents

        delegate :invoice, :subscription, to: :invoice_subscription
        delegate :organization, to: :invoice

        def pay_in_advance_first_period?
          subscription.plan.pay_in_advance? && !reconciliation_invoice_subscription
        end

        def reconciliation_invoice_subscription
          return @reconciliation_invoice_subscription if defined?(@reconciliation_invoice_subscription)

          @reconciliation_invoice_subscription = if subscription.plan.pay_in_advance?
            invoice_subscription.previous_invoice_subscription
          else
            invoice_subscription
          end
        end

        def commitment_boundaries
          {
            "from_datetime" => reconciliation_invoice_subscription.from_datetime,
            "to_datetime" => reconciliation_invoice_subscription.to_datetime
          }
        end

        def commitment_amount_cents
          @commitment_amount_cents ||= (minimum_commitment.amount_cents * proration_coefficient).round
        end

        def proration_coefficient
          @proration_coefficient ||= days_total.positive? ? days_active / days_total.to_f : 1.0
        end

        def days_active
          first_invoice_subscription = subscription.invoice_subscriptions
            .where("from_datetime >= ?", dates_service.previous_beginning_of_period)
            .order(Arel.sql("COALESCE(to_datetime, timestamp) ASC"))
            .first

          from_datetime = first_invoice_subscription&.from_datetime || reconciliation_invoice_subscription.from_datetime
          end_datetime = subscription.terminated? ? subscription.terminated_at : reconciliation_invoice_subscription.to_datetime

          ::Utils::Datetime.date_diff_with_timezone(
            from_datetime,
            end_datetime,
            subscription.customer.applicable_timezone
          )
        end

        def days_total
          ::Utils::Datetime.date_diff_with_timezone(
            dates_service.previous_beginning_of_period,
            dates_service.end_of_period,
            subscription.customer.applicable_timezone
          )
        end

        def dates_service
          @dates_service ||= ::Commitments::DatesService.new_instance(
            commitment: minimum_commitment,
            invoice_subscription: reconciliation_invoice_subscription
          ).call
        end

        def fees_total_amount_cents
          db_historical_fees_amount_cents + preview_fees_amount_cents
        end

        def fees_total_precise_amount_cents
          db_historical_fees_precise_amount_cents + preview_fees_precise_amount_cents
        end

        def db_historical_fees_amount_cents
          charge_fees.sum(:amount_cents) +
            charge_in_advance_fees.sum(:amount_cents) +
            fixed_charge_fees.sum(:amount_cents) +
            fixed_charge_in_advance_fees.sum(:amount_cents)
        end

        def db_historical_fees_precise_amount_cents
          charge_fees.sum(:precise_amount_cents) +
            charge_in_advance_fees.sum(:precise_amount_cents) +
            fixed_charge_fees.sum(:precise_amount_cents) +
            fixed_charge_in_advance_fees.sum(:precise_amount_cents)
        end

        def charge_fees
          charge_fees_base.where(charge: {pay_in_advance: false})
        end

        def charge_in_advance_fees
          charge_fees_base.where(charge: {pay_in_advance: true}, pay_in_advance: true)
        end

        def fixed_charge_fees
          fixed_charge_fees_base.where(fixed_charge: {pay_in_advance: false})
        end

        def fixed_charge_in_advance_fees
          fixed_charge_fees_base.where(fixed_charge: {pay_in_advance: true}, pay_in_advance: true)
        end

        def charge_fees_base
          @charge_fees_base ||= Fee.charge
            .joins(:charge)
            .where(subscription_id: subscription.id)
            .where("(fees.properties->>'charges_from_datetime')::timestamptz >= ?", dates_service.previous_beginning_of_period)
            .where("(fees.properties->>'charges_to_datetime')::timestamptz <= ?", dates_service.end_of_period&.iso8601(3))
        end

        def fixed_charge_fees_base
          @fixed_charge_fees_base ||= Fee.fixed_charge
            .joins(:fixed_charge)
            .where(subscription_id: subscription.id)
            .where("(fees.properties->>'fixed_charges_from_datetime')::timestamptz >= ?", dates_service.previous_beginning_of_period)
            .where("(fees.properties->>'fixed_charges_to_datetime')::timestamptz <= ?", dates_service.end_of_period&.iso8601(3))
        end

        def currency
          Money::Currency.new(subscription.plan.amount_currency)
        end
      end
    end
  end
end
