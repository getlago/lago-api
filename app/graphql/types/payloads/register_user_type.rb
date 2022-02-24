# frozen_string_literal: true

module Types
  module Payloads
    class RegisterUserType < Types::BaseObject
      field :user, Types::UserType, null: false
      field :organization, Types::OrganizationType, null: false
      field :membership, Types::MembershipType, null: false
    end
  end
end
