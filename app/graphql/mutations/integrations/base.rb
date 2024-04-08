# frozen_string_literal: true

module Mutations
  module Integrations
    class Base < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization
    end
  end
end
