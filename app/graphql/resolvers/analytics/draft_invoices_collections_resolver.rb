# frozen_string_literal: true

module Resolvers
  module Analytics
    class DraftInvoicesCollectionsResolver < Resolvers::BaseResolver
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "analytics:view"

      description "Query draft invoices collections of an organization"

      argument :currency, Types::CurrencyEnum, required: false

      type Types::Analytics::DraftInvoicesCollections::Object.collection_type, null: false

      def resolve(**args)
        raise unauthorized_error unless License.premium?

        ::Analytics::DraftInvoicesCollection.find_all_by(current_organization.id, **args.merge(months: 12))
      end
    end
  end
end
