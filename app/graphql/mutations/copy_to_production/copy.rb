# frozen_string_literal: true

module Mutations
  module CopyToProduction
    class Copy < BaseMutation
      include RequiresSelfServe
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

        return result.item if result.success?
        return result_error(result) unless result.missing_parent

        # Names the parent, so that the message tells which one to copy first.
        parent = result.missing_parent
        execution_error(
          error: "forbidden",
          status: 403,
          code: result.error.code,
          details: {item_type: parent.item_type, code: parent.record.code}
        )
      end
    end
  end
end
