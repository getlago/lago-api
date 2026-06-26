# frozen_string_literal: true

module Orders
  class UpdateService < BaseService
    include OrderForms::Premium

    Result = BaseResult[:order]

    def initialize(order:, params:)
      @order = order
      @params = params

      super
    end

    def call
      return result.not_found_failure!(resource: "order") unless order
      return result.forbidden_failure! unless order_forms_enabled?(order.organization)

      validate_execution_settings
      return result if result.failure?

      Order.transaction do
        Quotes::LockService.call(quote: order.quote) do
          order.reload
          next result.single_validation_failure!(field: :status, error_code: "not_editable") unless order.created?

          order.assign_attributes(params.slice(:execution_mode, :execute_at))
          order.save!

          result.order = order
        end
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :order, :params

    def effective_execution_mode
      params.key?(:execution_mode) ? params[:execution_mode] : order.execution_mode
    end

    def effective_execute_at
      params.key?(:execute_at) ? params[:execute_at] : order.execute_at
    end

    def validate_execution_settings
      validate_execution_mode
      return if result.failure?

      validate_execute_at
    end

    def validate_execution_mode
      return if effective_execution_mode.blank? && effective_execute_at.blank?

      if effective_execution_mode.blank?
        return result.single_validation_failure!(field: :execution_mode, error_code: "value_is_mandatory")
      end

      return if Order::EXECUTION_MODES.value?(effective_execution_mode.to_s)

      result.single_validation_failure!(field: :execution_mode, error_code: "value_is_invalid")
    end

    def validate_execute_at
      return unless params.key?(:execute_at)
      return if params[:execute_at].blank?
      return if Utils::Datetime.future_date?(params[:execute_at])

      result.single_validation_failure!(field: :execute_at, error_code: "invalid_date")
    end
  end
end
