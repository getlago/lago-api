# frozen_string_literal: true

module Types
  module Signups
    class VerificationStatusEnum < Types::BaseEnum
      graphql_name "SignupVerificationStatusEnum"

      %w[valid expired replaced locked already_verified invalid].each { value it }
    end
  end
end
