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
      ActiveRecord::Base.transaction do
        return result.not_found_failure!(resource: "role") unless role
        return result.forbidden_failure!(code: "predefined_role") if predefined_role?

        role.update!(params.slice(:name, :description, :permissions).compact)
        update_pending_invites if role.saved_change_to_name?
      end

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

    def update_pending_invites
      old_name = role.name_before_last_save
      role.organization.invites.pending.where("? = ANY(roles)", old_name).find_each do |invite|
        updated_roles = invite.roles.map { |r| (r == old_name) ? role.name : r }
        invite.update!(roles: updated_roles)
      end
    end
  end
end
