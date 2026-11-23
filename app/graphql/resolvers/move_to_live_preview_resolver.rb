# frozen_string_literal: true

module Resolvers
  class CopyToProductionPreviewResolver < Resolvers::BaseResolver
    include RequiresSelfServe
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = "copy_to_production:create"

    description "Previews moving a sandbox item to the sandbox's production organization"

    argument :id, ID, required: true, description: "ID of the item in the sandbox"
    argument :item_type, Types::CopyToProduction::ItemTypeEnum, required: true

    type Types::CopyToProduction::Preview, null: false

    def resolve(item_type:, id:)
      result = ::CopyToProduction::PreviewService.call(
        organization: current_organization,
        user: context[:current_user],
        item_type:,
        id:
      )

      result.success? ? result : result_error(result)
    end
  end
end
