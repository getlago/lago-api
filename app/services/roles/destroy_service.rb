# frozen_string_literal: true

module Roles
  class DestroyService < BaseService
    Result = BaseResult[:role]

    def initialize(role:)
      @role = role
      super
    end

    def call
      return result.not_found_failure!(resource: "role") unless role
      return result.forbidden_failure!(code: "predefined_role") if predefined_role?
      return result.forbidden_failure!(code: "role_assigned_to_members") if role.active_memberships.exists?

      role.discard!

      result.role = role
      result
    end

    private

    attr_reader :role

    def predefined_role?
      role.organization_id.nil?
    end
  end
end
