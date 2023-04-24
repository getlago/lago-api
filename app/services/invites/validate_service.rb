# frozen_string_literal: true

module Invites
  class ValidateService < BaseValidator
    def valid?
      valid_invite?
      valid_user?

      if errors?
        result.validation_failure!(errors:)
        return false
      end

      true
    end

    private

    def valid_invite?
      return true unless args[:current_organization].invites.pending.exists?(email: args[:email])

      add_error(field: :invite, error_code: 'invite_already_exists')
    end

    def valid_user?
      return true unless Membership.joins(:user)
        .where(organization_id: args[:current_organization].id)
        .where(users: { email: args[:email] })
        .active
        .exists?

      add_error(field: :email, error_code: 'email_already_used')
    end
  end
end
