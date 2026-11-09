# frozen_string_literal: true

module Types
  module Signups
    class EmailCheckObject < Types::BaseObject
      graphql_name "SignupEmailCheck"
      description "Whether self-serve signup accepts an email address"

      field :code, String, null: true, description: "Why the address is refused: value_is_mandatory, invalid_email_format or email_domain_not_allowed"
      field :valid, Boolean, null: false
    end
  end
end
