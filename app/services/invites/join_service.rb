# frozen_string_literal: true

module Invites
  class JoinService < BaseService
    Result = BaseResult[:invite, :membership]

    def initialize(user:, login_method:, token: nil, invite: nil)
      @token = token
      @invite = invite
      @user = user
      @login_method = login_method

      super
    end

    def call
      return result.not_found_failure!(resource: "invite") unless invite
      return result.not_found_failure!(resource: "user") unless user

      # NOTE: Emails are saved with the case the user typed, so compare them ignoring case.
      unless invite.email.casecmp?(user.email.to_s)
        return result.single_validation_failure!(field: :email, error_code: "invite_email_mistmatch")
      end

      unless invite.login_method_allowed?(login_method)
        return result.single_validation_failure!(error_code: "login_method_not_authorized", field: login_method)
      end

      if invite.organization.memberships.active.exists?(user_id: user.id)
        return result.single_validation_failure!(field: :email, error_code: "email_already_used")
      end

      ActiveRecord::Base.transaction do
        result.membership = Memberships::CreateFromInviteService.call!(invite:, user:).membership

        invite.recipient = result.membership
        invite.mark_as_accepted!
      end

      result.invite = invite
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :token, :user, :login_method

    def invite
      @invite ||= Invite.find_by(token:, status: :pending)
    end
  end
end
