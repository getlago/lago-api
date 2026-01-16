# frozen_string_literal: true

module Invites
  class UpdateService < BaseService
    def initialize(invite:, params:)
      @invite = invite
      @params = params

      super
    end

    def call
      return result.not_found_failure!(resource: "invite") unless invite
      return result.forbidden_failure!(code: "cannot_update_accepted_invite") if invite.accepted?
      return result.forbidden_failure!(code: "cannot_update_revoked_invite") if invite.revoked?
      return result unless valid_roles?

      invite.update!(roles: params[:roles])

      result.invite = invite
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :invite, :params

    def valid_roles?
      roles = params[:roles]
      if roles.blank?
        result.single_validation_failure!(field: :roles, error_code: "invalid_role")
        return false
      end

      organization_id = invite.organization_id
      found = Role.with_code(*roles).with_organization(organization_id).pluck(:code)
      missed = roles - found
      return true if missed.empty?

      result.single_validation_failure!(field: :roles, error_code: "invalid_role")
      false
    end
  end
end
