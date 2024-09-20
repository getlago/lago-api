# frozen_string_literal: true

module Types
  module CustomerPortal
    class QueryType < Types::BaseObject
      # Add `node(id: ID!) and `nodes(ids: [ID!]!)`
      include GraphQL::Types::Relay::HasNodeField
      include GraphQL::Types::Relay::HasNodesField

      field :customer_portal_invoice_collections, resolver: Resolvers::CustomerPortal::Analytics::InvoiceCollectionsResolver
      field :customer_portal_invoices, resolver: Resolvers::CustomerPortal::InvoicesResolver
      field :customer_portal_organization, resolver: Resolvers::CustomerPortal::OrganizationResolver
      field :customer_portal_overdue_balances, resolver: Resolvers::CustomerPortal::Analytics::OverdueBalancesResolver
      field :customer_portal_user, resolver: Resolvers::CustomerPortal::CustomerResolver
    end
  end
end
