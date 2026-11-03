# frozen_string_literal: true

module Events
  class ValidateApiInputService < BaseService
    Result = BaseResult

    STRING_FIELDS = %i[transaction_id code external_contract_id external_subscription_id].freeze

    def initialize(params:, batch: false)
      @params = params
      @batch = batch
      super
    end

    def call
      errors = if batch
        batch_errors
      else
        event_errors(params)
      end

      if errors.any?
        result.validation_failure!(errors:)
      end
      result
    end

    private

    attr_reader :params, :batch

    def batch_errors
      return {events: ["no_events"]} if params.nil? || params == []
      return {events: ["value_is_invalid"]} unless params.is_a?(Array)

      if params.size > CreateBatchService::MAX_LENGTH
        return {events: ["too_many_events"]}
      end

      params.each_with_index.with_object({}) do |(event, index), errors|
        event_errors(event).each do |field, codes|
          errors[ValidationFailure.item_field(:events, index, field)] = codes
        end
      end
    end

    def event_errors(event)
      return {base: ["value_is_invalid"]} unless event.is_a?(Hash)

      errors = STRING_FIELDS.each_with_object({}) do |field, values|
        values[field] = ["value_is_invalid"] unless event[field].nil? || event[field].is_a?(String)
      end

      %i[transaction_id code].each do |field|
        errors[field] ||= ["value_is_mandatory"] if event[field].blank?
      end

      if event.key?(:properties) && !event[:properties].nil? && !event[:properties].is_a?(Hash)
        errors[:properties] = ["value_is_invalid"]
      end

      if event.key?(:precise_total_amount_cents) && !valid_amount?(event[:precise_total_amount_cents])
        errors[:precise_total_amount_cents] = ["value_is_invalid"]
      end

      timestamp = event[:timestamp]
      unless timestamp.nil? || timestamp.is_a?(String) || timestamp.is_a?(Numeric)
        errors[:timestamp] = ["invalid_format"]
      end

      errors
    end

    def valid_amount?(value)
      case value
      when nil then true
      when String, Numeric then BigDecimal(value.to_s).finite?
      else false
      end
    rescue ArgumentError
      false
    end
  end
end
