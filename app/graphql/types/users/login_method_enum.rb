# frozen_string_literal: true

module Types
  module Users
    class LoginMethodEnum < Types::BaseEnum
      graphql_name "UserLoginMethod"

      User::LOGIN_METHODS.each do |type|
        value type
      end
    end
  end
end
