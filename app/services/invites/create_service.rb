# frozen_string_literal: true

module Invites
  class CreateService < BaseService
    def call(**args)
      existing_invite = Invite.find_by(
        organization_id: args[:organization_id],
        email: args[:email],
        status: :pending,
      )

      if existing_invite
        return result.fail!(
          code: 'invite_already_exists',
          message: 'Invite already exists',
        )
      end

      existing_membership = Membership.joins(:user).active.where(
        'organization_id = ? AND users.email = ?', args[:organization_id], args[:email]
      )

      if existing_membership.present?
        return result.fail!(
          code: 'email_already_used',
          message: 'A user with the same email already exists',
        )
      end

      invite = Invite.create!(
        organization_id: args[:organization_id],
        email: args[:email],
        token: generate_token,
      )

      result.invite = invite

      result
    rescue ActiveRecord::RecordInvalid => e
      result.fail_with_validations!(e.record)
    end

    private

    def generate_token
      token = SecureRandom.hex(20)

      return generate_token if Invite.exists?(token: token)

      token
    end
  end
end
