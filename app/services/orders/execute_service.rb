# frozen_string_literal: true

module Orders
  # Dispatches execution to the concrete service for the order's order_type.
  # Only one_off is supported for now.
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

      case order.order_type
      when Quote::ORDER_TYPES[:one_off]
        Orders::OneOff::ExecuteService.call(order:)
      else
        result.single_validation_failure!(field: :order_type, error_code: "unsupported_order_type")
      end
    end

    private

    attr_reader :order
  end
end
