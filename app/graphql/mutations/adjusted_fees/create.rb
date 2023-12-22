# frozen_string_literal: true

module Mutations
  module AdjustedFees
    class Create < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      graphql_name 'CreateAdjustedFee'
      description 'Creates Adjusted Fee'

      input_object_class Types::AdjustedFees::CreateInput

      type Types::Fees::Object

      def resolve(**args)
        validate_organization!

        fee = Fee.find_by(id: args[:fee_id])

        result = ::AdjustedFees::CreateService.call(
          organization: current_organization,
          fee:,
          params: args,
        )

        result.success? ? result.fee : result_error(result)
      end
    end
  end
end
