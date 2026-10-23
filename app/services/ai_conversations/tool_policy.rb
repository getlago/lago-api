# frozen_string_literal: true

module AiConversations
  # Maps every tool of the Lago MCP server to the member permissions the dashboard checks
  # for the same action. The AI agent only runs a tool when the member chatting holds all
  # of its permissions, and a write tool also waits for the member's confirmation.
  # A tool missing from this list is never exposed to the agent.
  module ToolPolicy
    # The finance assistant answers with SQL over the organization's billing data, so it
    # needs every view permission that data is shown under in the dashboard.
    FINANCE_ASSISTANT_PERMISSIONS = %w[
      analytics:view
      coupons:view
      credit_notes:view
      customers:view
      invoices:view
      payments:view
      plans:view
      subscriptions:view
    ].freeze

    Rule = Data.define(:permissions, :write) do
      def write? = write
    end

    def self.read(*permissions) = Rule.new(permissions:, write: false)

    def self.write(*permissions) = Rule.new(permissions:, write: true)

    RULES = {
      # Invoices and fees
      "get_invoice" => read("invoices:view"),
      "find_invoice_by_number" => read("invoices:view"),
      "list_invoices" => read("invoices:view"),
      "list_customer_invoices" => read("invoices:view"),
      "preview_invoice" => read("invoices:view"),
      "download_invoice" => read("invoices:view"),
      "list_fees" => read("invoices:view"),
      "get_fee" => read("invoices:view"),
      "create_invoice" => write("invoices:create"),
      "update_invoice" => write("invoices:update"),
      "refresh_invoice" => write("invoices:update"),
      "retry_invoice" => write("invoices:update"),
      "retry_invoice_payment" => write("invoices:update"),
      "void_invoice" => write("invoices:void"),
      "delete_invoice" => write("invoices:delete"),

      # Analytics
      "ask_lago_analytics" => read(*FINANCE_ASSISTANT_PERMISSIONS),

      # Customers
      "get_customer" => read("customers:view"),
      "list_customers" => read("customers:view"),
      "get_customer_current_usage" => read("customers:view"),
      # The API creates the customer or updates it when the external ID already exists.
      "create_customer" => write("customers:create", "customers:update"),

      # Subscriptions
      "get_subscription" => read("subscriptions:view"),
      "list_subscriptions" => read("subscriptions:view"),
      "list_customer_subscriptions" => read("subscriptions:view"),
      "create_subscription" => write("subscriptions:create"),
      "update_subscription" => write("subscriptions:update"),
      "delete_subscription" => write("subscriptions:update"),

      # Billable metrics
      "get_billable_metric" => read("billable_metrics:view"),
      "list_billable_metrics" => read("billable_metrics:view"),
      "create_billable_metric" => write("billable_metrics:create"),
      "update_billable_metric" => write("billable_metrics:update"),

      # Activity and API logs
      "get_activity_log" => read("audit_logs:view"),
      "list_activity_logs" => read("audit_logs:view"),
      "get_api_log" => read("audit_logs:view"),
      "list_api_logs" => read("audit_logs:view"),

      # Coupons
      "get_coupon" => read("coupons:view"),
      "list_coupons" => read("coupons:view"),
      "list_applied_coupons" => read("coupons:view"),
      "create_coupon" => write("coupons:create"),
      "update_coupon" => write("coupons:update"),
      "delete_coupon" => write("coupons:delete"),
      "apply_coupon" => write("coupons:attach"),

      # Events: the dashboard shows them, with the API keys that send them, under developers:manage
      "get_event" => read("developers:manage"),
      "list_events" => read("developers:manage"),
      "create_event" => write("developers:manage"),

      # Credit notes
      "get_credit_note" => read("credit_notes:view"),
      "list_credit_notes" => read("credit_notes:view"),
      "create_credit_note" => write("credit_notes:create"),
      "update_credit_note" => write("credit_notes:update"),

      # Plans
      "get_plan" => read("plans:view"),
      "list_plans" => read("plans:view"),
      "create_plan" => write("plans:create"),
      "update_plan" => write("plans:update"),
      "delete_plan" => write("plans:delete"),

      # Payments
      "get_payment" => read("payments:view"),
      "list_payments" => read("payments:view"),
      "list_customer_payments" => read("payments:view"),
      "create_payment" => write("payments:create")
    }.freeze

    def self.rule(tool_name)
      RULES[tool_name.to_s]
    end

    def self.known?(tool_name)
      RULES.key?(tool_name.to_s)
    end

    def self.missing_permissions(membership, tool_name)
      rule(tool_name).permissions.reject { |permission| membership.can?(permission) }
    end
  end
end
