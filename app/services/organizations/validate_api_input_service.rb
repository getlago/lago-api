# frozen_string_literal: true

module Organizations
  class ValidateApiInputService < BaseService
    Result = BaseResult

    def initialize(params:)
      @params = params
      super
    end

    def call
      if params.key?(:slug) && !params[:slug].nil? && !params[:slug].is_a?(String)
        return result.single_validation_failure!(field: :slug, error_code: "value_is_invalid")
      end

      result
    end

    private

    attr_reader :params
  end
end
