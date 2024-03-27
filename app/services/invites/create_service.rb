# frozen_string_literal: true

module Invites
  class CreateService < BaseService
    def call(**args)
      return result unless valid?(**args)

      result.invite = Invite.create!(
        organization_id: args[:current_organization].id,
        email: args[:email],
        token: generate_token
      )

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    def generate_token
      token = SecureRandom.hex(20)

      return generate_token if Invite.exists?(token:)

      token
    end

    def valid?(**args)
      Invites::ValidateService.new(result, **args).valid?
    end
  end
end
