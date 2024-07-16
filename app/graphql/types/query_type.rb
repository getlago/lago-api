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
    field :credit_note_estimate, resolver: Resolvers::CreditNotes::EstimateResolver
    field :credit_notes, resolver: Resolvers::CreditNotesResolver
    field :current_version, resolver: Resolvers::VersionResolver
    field :customer, resolver: Resolvers::CustomerResolver
    field :customer_invoices, resolver: Resolvers::Customers::InvoicesResolver
    field :customer_portal_invoice_collections, resolver: Resolvers::CustomerPortal::Analytics::InvoiceCollectionsResolver
    field :customer_portal_invoices, resolver: Resolvers::CustomerPortal::InvoicesResolver
    field :customer_portal_organization, resolver: Resolvers::CustomerPortal::OrganizationResolver
    field :customer_portal_overdue_balances, resolver: Resolvers::CustomerPortal::Analytics::OverdueBalancesResolver
    field :customer_portal_user, resolver: Resolvers::CustomerPortal::CustomerResolver
    field :customer_usage, resolver: Resolvers::Customers::UsageResolver
    field :customers, resolver: Resolvers::CustomersResolver
    field :events, resolver: Resolvers::EventsResolver
    field :google_auth_url, resolver: Resolvers::Auth::Google::AuthUrlResolver
    field :gross_revenues, resolver: Resolvers::Analytics::GrossRevenuesResolver
    field :integration, resolver: Resolvers::IntegrationResolver
    field :integration_collection_mapping, resolver: Resolvers::IntegrationCollectionMappingResolver
    field :integration_collection_mappings, resolver: Resolvers::IntegrationCollectionMappingsResolver
    field :integration_items, resolver: Resolvers::IntegrationItemsResolver
    field :integration_mapping, resolver: Resolvers::IntegrationMappingResolver
    field :integration_mappings, resolver: Resolvers::IntegrationMappingsResolver
    field :integration_subsidiaries, resolver: Resolvers::Integrations::SubsidiariesResolver
    field :integrations, resolver: Resolvers::IntegrationsResolver
    field :invite, resolver: Resolvers::InviteResolver
    field :invites, resolver: Resolvers::InvitesResolver
    field :invoice, resolver: Resolvers::InvoiceResolver
    field :invoice_collections, resolver: Resolvers::Analytics::InvoiceCollectionsResolver
    field :invoice_credit_notes, resolver: Resolvers::InvoiceCreditNotesResolver
    field :invoiced_usages, resolver: Resolvers::Analytics::InvoicedUsagesResolver
    field :invoices, resolver: Resolvers::InvoicesResolver
    field :memberships, resolver: Resolvers::MembershipsResolver
    field :mrrs, resolver: Resolvers::Analytics::MrrsResolver
    field :organization, resolver: Resolvers::OrganizationResolver
    field :overdue_balances, resolver: Resolvers::Analytics::OverdueBalancesResolver
    field :password_reset, resolver: Resolvers::PasswordResetResolver
    field :payment_provider, resolver: Resolvers::PaymentProviderResolver
    field :payment_providers, resolver: Resolvers::PaymentProvidersResolver
    field :plan, resolver: Resolvers::PlanResolver
    field :plans, resolver: Resolvers::PlansResolver
    field :subscription, resolver: Resolvers::SubscriptionResolver
    field :subscriptions, resolver: Resolvers::SubscriptionsResolver
    field :tax, resolver: Resolvers::TaxResolver
    field :taxes, resolver: Resolvers::TaxesResolver
    field :wallet, resolver: Resolvers::WalletResolver
    field :wallet_transactions, resolver: Resolvers::WalletTransactionsResolver
    field :wallets, resolver: Resolvers::WalletsResolver
    field :webhook_endpoint, resolver: Resolvers::WebhookEndpointResolver
    field :webhook_endpoints, resolver: Resolvers::WebhookEndpointsResolver
    field :webhooks, resolver: Resolvers::WebhooksResolver
  end
end
