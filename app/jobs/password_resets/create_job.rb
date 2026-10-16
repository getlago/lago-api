# frozen_string_literal: true

module PasswordResets
  # Looks up the user and creates the password reset outside of the request, so the response time of
  # createPasswordReset is the same whether or not the email belongs to a user.
  class CreateJob < ApplicationJob
    queue_as :default

    def perform(email)
      user = User.find_by(email:)

      PasswordResets::CreateService.call!(user:)
    end
  end
end
