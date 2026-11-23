# frozen_string_literal: true

module Mutations
  module CopyToProduction
    class Copy < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "copy_to_production:create"

      graphql_name "CopyToProduction"
      description "Copies a sandbox item, with the items it references, to the sandbox's production organization"

      input_object_class Types::CopyToProduction::CopyInput

      type Types::CopyToProduction::Item

      def resolve(item_type:, id:)
        result = ::CopyToProduction::CopyService.call(
          organization: current_organization,
          user: context[:current_user],
          item_type:,
          id:
        )

        result.success? ? result.item : result_error(result)
      end
    end
  end
end
