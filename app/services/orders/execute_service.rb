# frozen_string_literal: true

module Orders
  class ExecuteService < BaseService
    include OrderForms::Premium

    Result = BaseResult[:order]

    def initialize(order:)
      @order = order

      super
    end

    def call
      return result.not_found_failure!(resource: "order") unless order
      return result.forbidden_failure! unless order_forms_enabled?(order.organization)

      Order.transaction do
        Quotes::LockService.call(quote: order.quote) do
          order.reload
          next result.single_validation_failure!(field: :status, error_code: "not_executable") unless order.created?
          next result.single_validation_failure!(field: :execution_mode, error_code: "value_is_mandatory") if order.execution_mode.blank?

          # TODO: delegate to the order_type execution service (billing, execution_record, webhook)
          order.update!(status: :executed, executed_at: Time.current)

          result.order = order
        end
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :order
  end
end
