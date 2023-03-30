# frozen_string_literal: true

module Types
  # QueryType
  class QueryType < Types::BaseObject
    # Add `node(id: ID!) and `nodes(ids: [ID!]!)`
    include GraphQL::Types::Relay::HasNodeField
    include GraphQL::Types::Relay::HasNodesField

    field :current_user, resolver: Resolvers::CurrentUserResolver

    field :add_on, resolver: Resolvers::AddOnResolver
    field :add_ons, resolver: Resolvers::AddOnsResolver
    field :billable_metric, resolver: Resolvers::BillableMetricResolver
    field :billable_metrics, resolver: Resolvers::BillableMetricsResolver
    field :coupon, resolver: Resolvers::CouponResolver
    field :coupons, resolver: Resolvers::CouponsResolver
    field :credit_note, resolver: Resolvers::CreditNoteResolver
    field :current_version, resolver: Resolvers::VersionResolver
    field :customer, resolver: Resolvers::CustomerResolver
    field :customer_credit_notes, resolver: Resolvers::CustomerCreditNotesResolver
    field :customer_invoices, resolver: Resolvers::Customers::InvoicesResolver
    field :customer_portal_invoices, resolver: Resolvers::CustomerPortal::InvoicesResolver
    field :customer_portal_organization, resolver: Resolvers::CustomerPortal::OrganizationResolver
    field :customer_portal_user, resolver: Resolvers::CustomerPortal::CustomerResolver
    field :customer_usage, resolver: Resolvers::Customers::UsageResolver
    field :customers, resolver: Resolvers::CustomersResolver
    field :events, resolver: Resolvers::EventsResolver
    field :invite, resolver: Resolvers::InviteResolver
    field :invites, resolver: Resolvers::InvitesResolver
    field :invoice, resolver: Resolvers::InvoiceResolver
    field :invoice_credit_notes, resolver: Resolvers::InvoiceCreditNotesResolver
    field :invoices, resolver: Resolvers::InvoicesResolver
    field :memberships, resolver: Resolvers::MembershipsResolver
    field :organization, resolver: Resolvers::OrganizationResolver
    field :password_reset, resolver: Resolvers::PasswordResetResolver
    field :plan, resolver: Resolvers::PlanResolver
    field :plans, resolver: Resolvers::PlansResolver
    field :wallet_transactions, resolver: Resolvers::WalletTransactionsResolver
    field :wallets, resolver: Resolvers::WalletsResolver
    field :webhooks, resolver: Resolvers::WebhooksResolver
  end
end
