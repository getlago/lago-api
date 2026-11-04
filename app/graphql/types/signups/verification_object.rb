# frozen_string_literal: true

module Types
  module Signups
    class VerificationObject < Types::BaseObject
      graphql_name "SignupVerification"
      description "The state of a self-serve signup verification link"

      field :email, String, null: true, description: "Set only when the link is valid"
      field :password_required, Boolean, null: false, description: "True unless the signup secret of the attempt that sent this link is given"
      field :status, Types::Signups::VerificationStatusEnum, null: false
    end
  end
end
