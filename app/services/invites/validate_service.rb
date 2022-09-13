# frozen_string_literal: true

module Invites
  class ValidateService
    def initialize(result, **args)
      @result = result
      @args = args
    end

    def valid?
      errors = {}
      errors = errors.merge({ 'invite': ['invite_already_exists'] } ) if invalid_invite?
      errors = errors.merge({ 'email': ['email_already_used'] }) if invalid_user?

      unless errors.empty?
        result.fail!(
          code: 'unprocessable_entity',
          message: 'Validation error on the record',
          details: errors,
        )
        return false
      end

      true
    end

    private

    attr_accessor :result, :args

    def invalid_invite?
      args[:current_organization].invites.pending.exists?(email: args[:email])
    end

    def invalid_user?
      Membership.joins(:user).active.where(
        'organization_id = ? AND users.email = ?', args[:current_organization].id, args[:email]
      ).exists?
    end
  end
end
