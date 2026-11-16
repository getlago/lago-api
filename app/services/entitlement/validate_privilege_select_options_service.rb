# frozen_string_literal: true

module Entitlement
  # Checks the select_options of a privilege input against its value_type and builds the config
  # to store. The shape is checked here so that errors are reported on select_options, not config.
  class ValidatePrivilegeSelectOptionsService < BaseService
    Result = BaseResult[:config]

    def initialize(value_type:, params:)
      @value_type = value_type
      @params = params
      super
    end

    def call
      if !options.nil? && !valid_shape?
        result.single_validation_failure!(field: :select_options, error_code: "value_is_invalid")
      elsif select? && options.blank?
        result.single_validation_failure!(field: :select_options, error_code: "value_is_mandatory")
      elsif !select? && !options.nil?
        result.single_validation_failure!(field: :select_options, error_code: "value_must_be_blank")
      else
        result.config = select? ? {"select_options" => options} : {}
      end

      result
    end

    private

    attr_reader :value_type, :params

    def options
      params[:select_options]
    end

    def select?
      value_type == "select"
    end

    def valid_shape?
      options.is_a?(Array) && options.all?(String)
    end
  end
end
