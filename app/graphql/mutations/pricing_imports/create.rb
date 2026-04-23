# frozen_string_literal: true

module Mutations
  module PricingImports
    class Create < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      graphql_name "CreatePricingImport"
      description "Parses a pricing file via Claude and stores the proposal as a draft"

      argument :source_filename, String, required: true
      argument :file_text, String, required: true

      type Types::PricingImports::Object

      def resolve(source_filename:, file_text:)
        membership = current_organization.memberships.find_by(user_id: context[:current_user].id)

        result = ::PricingImports::CreateService.call(
          organization: current_organization,
          membership: membership,
          source_filename: source_filename,
          file_text: file_text
        )

        result.success? ? result.pricing_import : result_error(result)
      end
    end
  end
end
