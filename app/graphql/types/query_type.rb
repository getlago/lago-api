# frozen_string_literal: true

module Types
  # QueryType
  class QueryType < Types::BaseObject
    # Add `node(id: ID!) and `nodes(ids: [ID!]!)`
    include GraphQL::Types::Relay::HasNodeField
    include GraphQL::Types::Relay::HasNodesField

    field :current_user, resolver: Resolvers::CurrentUserResolver

    field :add_ons, resolver: Resolvers::AddOnsResolver
    field :add_on, resolver: Resolvers::AddOnResolver
    field :billable_metrics, resolver: Resolvers::BillableMetricsResolver
    field :billable_metric, resolver: Resolvers::BillableMetricResolver
    field :coupons, resolver: Resolvers::CouponsResolver
    field :coupon, resolver: Resolvers::CouponResolver
    field :customers, resolver: Resolvers::CustomersResolver
    field :customer, resolver: Resolvers::CustomerResolver
    field :events, resolver: Resolvers::EventsResolver
    field :customer_usage, resolver: Resolvers::Customers::UsageResolver
    field :plans, resolver: Resolvers::PlansResolver
    field :plan, resolver: Resolvers::PlanResolver
    field :current_version, resolver: Resolvers::VersionResolver
    field :wallets, resolver: Resolvers::WalletsResolver
    field :wallet, resolver: Resolvers::WalletResolver
    field :wallet_transactions, resolver: Resolvers::WalletTransactionsResolver
    field :wallet_transaction, resolver: Resolvers::WalletTransactionResolver
  end
end
