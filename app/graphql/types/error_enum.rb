module Types
  class ErrorEnum < BaseEnum
    value 'internal_error'
    value 'unauthorized'
    value 'token_encoding_error'
    value 'expired_jwt_token'

    value 'incorrect_login_or_password'
    value 'user_already_exists'
  end
end
