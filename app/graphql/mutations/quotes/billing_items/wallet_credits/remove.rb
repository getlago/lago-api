# frozen_string_literal: true

module Mutations
  module Quotes
    module BillingItems
      module WalletCredits
        class Remove < BaseMutation
          include AuthenticableApiUser
          include RequiredOrganization

          REQUIRED_PERMISSION = "quotes:update"

          graphql_name "RemoveQuoteWalletCredit"
          description "Removes a wallet credit billing item from a quote version"

          argument :quote_version_id, ID, required: true
          argument :id, ID, required: true

          type Types::QuoteVersions::Object

          def resolve(**args)
            quote_version = current_organization.quote_versions.find_by(id: args[:quote_version_id])
            result = ::Quotes::BillingItems::WalletCredits::RemoveService.call(
              quote_version:,
              id: args[:id]
            )
            result.success? ? result.quote_version : result_error(result)
          end
        end
      end
    end
  end
end
