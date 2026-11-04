# frozen_string_literal: true

module Types
  module Payloads
    class LoginUserType < Types::BaseObject
      field :needs_organization, Boolean, null: false, description: "True for a self-serve user who must create an organization (signup Step 3)"
      field :token, String, null: false
      field :user, Types::UserType, null: false

      def needs_organization
        object.user.needs_organization?
      end
    end
  end
end
