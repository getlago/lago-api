# frozen_string_literal: true

module Orders
  module OneOff
    # Internal: premium/feature-flag gates live in Orders::ExecuteService, always call through it.
    class ExecuteService < BaseService
      Result = BaseResult[:order]

      def initialize(order:)
        @order = order

        super
      end

      def call
        return success_result if order.executed?

        if order.execution_mode.blank?
          return result.single_validation_failure!(field: :execution_mode, error_code: "value_is_mandatory")
        end

        Order.transaction do
          Quotes::LockService.call(quote: order.quote) do
            order.reload
            next success_result if order.executed?

            invoice = execute_in_lago? ? bill_one_off : nil
            mark_executed!(invoice)

            result.order = order
          end
        end

        result
      rescue ActiveRecord::RecordInvalid => e
        record_execution_failure!(result.record_validation_failure!(record: e.record))
      rescue BaseService::FailedResult => e
        record_execution_failure!(e.result)
      end

      private

      attr_reader :order

      def success_result
        result.order = order
        result
      end

      def execute_in_lago?
        order.execution_mode == Order::EXECUTION_MODES[:execute_in_lago]
      end

      def mark_executed!(invoice)
        executed_at = Time.current

        order.update!(
          status: :executed,
          executed_at:,
          execution_record: {
            executed_at: executed_at.iso8601,
            execution_mode: order.execution_mode,
            invoice_id: invoice&.id,
            errors: []
          }
        )
      end

      # The transaction has already rolled back, so this trace is the only durable outcome
      # of the attempt. Recording it moves the order to failed, excluding it from the
      # executable scope; retrying is a deliberate manual action.
      def record_execution_failure!(failed_result)
        order.update!(
          status: :failed,
          executed_at: nil,
          execution_record: {
            executed_at: nil,
            execution_mode: order.execution_mode,
            invoice_id: nil,
            errors: execution_errors(failed_result.error)
          }
        )

        failed_result
      end

      def execution_errors(error)
        if error.respond_to?(:messages)
          error.messages.values.flatten
        elsif error.respond_to?(:code)
          [error.code]
        else
          [error.message]
        end
      end

      def bill_one_off
        Invoices::CreateOneOffService.call!(
          customer: order.customer,
          currency: order.currency,
          fees: build_fees,
          timestamp: Time.current.to_i,
          with_discarded_add_ons: true
        ).invoice
      end

      def build_fees
        add_on_items.map do |item|
          {
            add_on_id: item["id"],
            units: effective_value(item, "units"),
            unit_amount_cents: effective_value(item, "unitAmountCents"),
            invoice_display_name: effective_value(item, "invoiceDisplayName"),
            # Description may ride in either section (the payload is free-form); overrides win.
            # When neither carries one, the fee falls back to the add-on description in
            # Fees::OneOffService.
            description: effective_value(item, "description"),
            from_datetime: effective_value(item, "fromDatetime"),
            to_datetime: effective_value(item, "toDatetime")
          }
        end
      end

      def effective_value(item, field)
        item.dig("overrides", field) || item.dig("payload", field)
      end

      def add_on_items
        Array((quote_version.billing_items || {})["addOns"])
      end

      def quote_version
        order.quote_version
      end
    end
  end
end
