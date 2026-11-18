# frozen_string_literal: true

module Types
  module Payloads
    class LoginUserType < Types::BaseObject
      field :needs_organization, Boolean, null: false, description: "True for a self-serve user who must create an organization (signup Step 3)"
      field :token, String, null: false
      field :user, Types::UserType, null: false

      # Password login answers it from the check it already ran; the other sign-in paths compute it here.
      def needs_organization
        known = object.try(:needs_organization)
        known.nil? ? object.user.needs_organization? : known
      end
    end
  end
end
