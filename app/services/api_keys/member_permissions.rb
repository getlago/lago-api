# frozen_string_literal: true

module ApiKeys
  # The permissions of a key minted for a member. An API key has read and write per resource,
  # which is coarser than the permissions of a role. So read requires every view permission the
  # resource is shown under, and write requires every permission for what the API can change on
  # it: the key never allows more than the member can do in the dashboard. A resource missing
  # from the rules is left to admins.
  module MemberPermissions
    extend self

    def self.crud(group)
      {read: ["#{group}:view"], write: %W[#{group}:create #{group}:update #{group}:delete]}
    end

    RULES = {
      "activity_log" => {read: %w[audit_logs:view]},
      "add_on" => crud("addons"),
      "analytic" => {read: %w[analytics:view data_api:view]},
      "api_log" => {read: %w[audit_logs:view]},
      "applied_coupon" => {read: %w[coupons:view], write: %w[coupons:attach coupons:detach]},
      "attributed_usage" => {read: %w[attributed_usage:view customers:view]},
      "billable_metric" => crud("billable_metrics"),
      "billing_entity" => crud("billing_entities"),
      "contract" => {read: %w[contracts:view], write: %w[contracts:create contracts:update contracts:terminate]},
      "contract_rate_card" => {read: %w[contracts:view], write: %w[contracts:create contracts:update]},
      "coupon" => crud("coupons"),
      "credit_note" => {
        read: %w[credit_notes:view],
        write: %w[credit_notes:create credit_notes:update credit_notes:void credit_notes:send]
      },
      "customer" => crud("customers"),
      "customer_usage" => {read: %w[customers:view]},
      # The dashboard shows events, with the keys that send them, to the members who manage developers.
      "event" => {read: %w[developers:manage], write: %w[developers:manage]},
      "feature" => crud("features"),
      "fee" => {read: %w[invoices:view]},
      "invoice" => {
        read: %w[invoices:view],
        write: %w[invoices:create invoices:update invoices:void invoices:delete invoices:send]
      },
      "lifetime_usage" => {read: %w[subscriptions:view], write: %w[subscriptions:update]},
      "order" => {read: %w[orders:view], write: %w[orders:update orders:execute]},
      "order_form" => {read: %w[order_forms:view], write: %w[order_forms:sign order_forms:void]},
      "organization" => {read: %w[organization:view], write: %w[organization:update]},
      "payment" => {read: %w[payments:view], write: %w[payments:create]},
      "payment_method" => crud("payment_methods"),
      "payment_request" => {read: %w[invoices:view payments:view]},
      "plan" => crud("plans"),
      "plan_rate_card" => {read: %w[plans:view rate_cards:view], write: crud("plans")[:write] + crud("rate_cards")[:write]},
      "product" => crud("products"),
      "product_category" => crud("products"),
      "quote" => {
        read: %w[quotes:view],
        write: %w[quotes:create quotes:update quotes:approve quotes:clone quotes:void]
      },
      "rate_card" => crud("rate_cards"),
      "security_log" => {read: %w[security_logs:view]},
      "subscription" => {read: %w[subscriptions:view], write: %w[subscriptions:create subscriptions:update]},
      "tax" => {read: %w[organization:taxes:view], write: %w[organization:taxes:update]},
      "usage_attribution_type" => crud("usage_attribution_types"),
      "wallet" => {read: %w[customers:view], write: %w[wallets:create wallets:update wallets:top_up wallets:terminate]},
      "wallet_transaction" => {read: %w[customers:view], write: %w[wallets:top_up]},
      "webhook_endpoint" => {read: %w[developers:manage], write: %w[developers:manage]},
      "webhook_jwt_public_key" => {read: %w[developers:manage]}
    }.freeze

    def for(membership)
      return ApiKey.default_permissions if membership.admin?

      held = membership.permissions_hash

      ApiKey::RESOURCES.index_with do |resource|
        (RULES[resource] || {}).filter_map do |mode, required|
          mode.to_s if required.all? { |permission| held[permission] }
        end
      end
    end
  end
end
