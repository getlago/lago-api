# frozen_string_literal: true

module Resolvers
  module Admin
    class CsAdminsResolver < Resolvers::BaseResolver
      include AuthenticableAdminUser

      description "List CS admin users (admin only)"

      type [Types::UserType], null: false

      def resolve
        User.where(cs_admin: true).order(:email)
      end
    end
  end
end
