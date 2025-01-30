# frozen_string_literal: true

module Resolvers
  module Analytics
    class RevenueStreamsResolver < Resolvers::BaseResolver
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "analytics:view"

      description "Query revenue streams of an organization"

      argument :currency, Types::CurrencyEnum, required: false
      argument :from_date, GraphQL::Types::ISO8601Date, required: false
      argument :to_date, GraphQL::Types::ISO8601Date, required: false
      argument :country, Types::CountryCodeEnum, required: false
      argument :external_customer_id, String, required: false
      argument :customer_type, Types::Customers::CustomerTypeEnum, required: false
      argument :plan_code, String, required: false
      argument :external_subscription_id, String, required: false

      type Types::Analytics::RevenueStreams::Object.collection_type, null: false

      def resolve(**args)
        raise unauthorized_error unless current_organization.analytics_revenue_streams_enabled?

        #::Analytics::RevenueStream.find_all_by(current_organization.id, **args)
        [
          {
              "organization_id": "2537afc4-0e7c-4abb-89b7-d9b28c35780b",
              "from_date": "2024-10-31",
              "to_date": "2024-10-31",
              "currency": "EUR",
              "gross_revenue_amount_cents": 2015000,
              "in_advance_fee_amount_cents": 0,
              "usage_based_fee_amount_cents": 2015000,
              "one_off_fee_amount_cents": 0,
              "subscription_fee_amount_cents": 0,
              "commitment_fee_amount_cents": 0,
              "coupons_amount_cents": 0,
              "net_revenue_amount_cents": 2015000
          },
          {
              "organization_id": "2537afc4-0e7c-4abb-89b7-d9b28c35780b",
              "from_date": "2024-11-30",
              "to_date": "2024-11-30",
              "currency": "EUR",
              "gross_revenue_amount_cents": 2080000,
              "in_advance_fee_amount_cents": 0,
              "usage_based_fee_amount_cents": 2080000,
              "one_off_fee_amount_cents": 0,
              "subscription_fee_amount_cents": 0,
              "commitment_fee_amount_cents": 0,
              "coupons_amount_cents": 0,
              "net_revenue_amount_cents": 2080000
          },
          {
              "organization_id": "2537afc4-0e7c-4abb-89b7-d9b28c35780b",
              "from_date": "2024-11-30",
              "to_date": "2024-11-30",
              "currency": "USD",
              "gross_revenue_amount_cents": 0,
              "in_advance_fee_amount_cents": 0,
              "usage_based_fee_amount_cents": 0,
              "one_off_fee_amount_cents": 0,
              "subscription_fee_amount_cents": 0,
              "commitment_fee_amount_cents": 0,
              "coupons_amount_cents": 0,
              "net_revenue_amount_cents": 0
          },
          {
              "organization_id": "2537afc4-0e7c-4abb-89b7-d9b28c35780b",
              "from_date": "2024-12-31",
              "to_date": "2024-12-31",
              "currency": "USD",
              "gross_revenue_amount_cents": 3333,
              "in_advance_fee_amount_cents": 0,
              "usage_based_fee_amount_cents": 0,
              "one_off_fee_amount_cents": 0,
              "subscription_fee_amount_cents": 3333,
              "commitment_fee_amount_cents": 0,
              "coupons_amount_cents": 0,
              "net_revenue_amount_cents": 3333
          },
          {
              "organization_id": "2537afc4-0e7c-4abb-89b7-d9b28c35780b",
              "from_date": "2025-01-31",
              "to_date": "2025-01-31",
              "currency": "EUR",
              "gross_revenue_amount_cents": 2145335,
              "in_advance_fee_amount_cents": 335,
              "usage_based_fee_amount_cents": 2145000,
              "one_off_fee_amount_cents": 0,
              "subscription_fee_amount_cents": 0,
              "commitment_fee_amount_cents": 0,
              "coupons_amount_cents": 0,
              "net_revenue_amount_cents": 2145335
          },
          {
              "organization_id": "2537afc4-0e7c-4abb-89b7-d9b28c35780b",
              "from_date": "2025-01-31",
              "to_date": "2025-01-31",
              "currency": "USD",
              "gross_revenue_amount_cents": 3024,
              "in_advance_fee_amount_cents": 0,
              "usage_based_fee_amount_cents": 0,
              "one_off_fee_amount_cents": 24,
              "subscription_fee_amount_cents": 3000,
              "commitment_fee_amount_cents": 0,
              "coupons_amount_cents": 0,
              "net_revenue_amount_cents": 3024
          }
        ]
      end
    end
  end
end
