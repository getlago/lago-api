# frozen_string_literal: true

module Invites
  class ValidateService
    def initialize(result, **args)
      @result = result
      @args = args
    end

    def valid?
      errors = {}
      errors = errors.merge(valid_invite?) if valid_invite?
      errors = errors.merge(valid_user?) if valid_user?

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

    def valid_invite?
      result.current_organization = args[:current_organization]

      { 'invite': ['invite_already_exists'] } if args[:current_organization].invites.pending.exists?(email: args[:email])
    end

    def valid_user?
      existing_membership = Membership.joins(:user).active.where(
        'organization_id = ? AND users.email = ?', args[:current_organization].id, args[:email]
      )
      { 'email': ['email_already_used'] } if existing_membership.present?
    end
  end
end
