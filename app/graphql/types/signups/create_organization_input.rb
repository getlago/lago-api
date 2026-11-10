# frozen_string_literal: true

module Types
  module Signups
    class CreateOrganizationInput < BaseInputObject
      graphql_name "CreateSelfServeOrganizationInput"
      description "Signup Step 3 answers: the organization name, and the role and source sent to analytics only"

      argument :name, String, required: true
      argument :role, Types::Signups::RoleEnum, required: true
      argument :source, Types::Signups::SourceEnum, required: false
    end
  end
end
