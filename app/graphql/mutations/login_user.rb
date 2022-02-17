# frozen_string_literal: true

# Mutations::LoginUser Mutation
module Mutations
  class LoginUser < BaseMutation
    argument :email, String, required: true
    argument :password, String, required: true

    type Types::Payloads::LoginUserType

    def resolve(email:, password:)
      result = UsersService.new.login(email, password)
      result.success? ? result : execution_error(message: result.error)
    end
  end
end
