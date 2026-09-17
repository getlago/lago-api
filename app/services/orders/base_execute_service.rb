# frozen_string_literal: true

module Orders
  # Internal: premium/feature-flag gates live in Orders::ExecuteService, always call through it.
  # Subclasses implement create_records, returning the ids of what they created for the execution
  # record.
  class BaseExecuteService < BaseService
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

          mark_executed!(execute_in_lago? ? create_records : {})

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

    def create_records
      raise NotImplementedError
    end

    def success_result
      result.order = order
      result
    end

    def execute_in_lago?
      order.execution_mode == Order::EXECUTION_MODES[:execute_in_lago]
    end

    def mark_executed!(created)
      executed_at = Time.current

      order.update!(
        status: :executed,
        executed_at:,
        execution_record: execution_record(executed_at: executed_at.iso8601, **created)
      )

      SendWebhookJob.perform_after_commit("order.executed", order)
      Utils::ActivityLog.produce_after_commit(order, "order.executed")
    end

    # The transaction has already rolled back, so this trace is the only durable outcome of the
    # attempt. Recording it moves the order to failed, excluding it from the executable scope;
    # retrying is a deliberate manual action.
    def record_execution_failure!(failed_result)
      order.update!(
        status: :failed,
        executed_at: nil,
        execution_record: execution_record(errors: execution_errors(failed_result.error))
      )

      failed_result
    end

    def execution_record(**written)
      Order::EXECUTION_RECORD_DEFAULTS
        .merge("execution_mode" => order.execution_mode)
        .merge(written.stringify_keys)
    end

    def billing_items
      @billing_items ||= order.billing_snapshot || {}
    end

    # A negotiated value overrides the catalog snapshot it was drafted from.
    def effective_value(item, field)
      item.dig("overrides", field) || item.dig("payload", field)
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
  end
end
