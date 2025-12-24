# frozen_string_literal: true

module Roles
  class UpdateService < BaseService
    Result = BaseResult[:role]

    def initialize(role:, params:)
      @role = role
      @params = params
      super
    end

    def call
      return result.not_found_failure!(resource: "role") unless role
      return result.forbidden_failure!(code: "predefined_role") if predefined_role?

      role.update!(params.slice(:name, :description, :permissions).compact)

      result.role = role
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :role, :params

    def predefined_role?
      role.organization_id.nil?
    end
  end
end
