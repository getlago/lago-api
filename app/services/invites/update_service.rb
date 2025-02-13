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

      invite.update!(
        role: params[:role]
      )

      result.invite = invite
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :invite, :params
  end
end
