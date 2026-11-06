# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiConversations::ToolPolicy do
  # Tools of the Lago MCP server (lago-agent-toolkit, mcp/src/server.rs)
  let(:write_tools) do
    %w[
      create_invoice update_invoice refresh_invoice retry_invoice retry_invoice_payment void_invoice delete_invoice
      create_customer
      create_subscription update_subscription delete_subscription
      create_billable_metric update_billable_metric
      create_coupon update_coupon delete_coupon apply_coupon
      create_event
      create_credit_note update_credit_note
      create_plan update_plan delete_plan
      create_payment
    ]
  end

  let(:read_tools) do
    %w[
      get_invoice find_invoice_by_number list_invoices list_customer_invoices preview_invoice download_invoice
      list_fees get_fee ask_lago_analytics
      get_customer list_customers get_customer_current_usage
      get_subscription list_subscriptions list_customer_subscriptions
      get_billable_metric list_billable_metrics
      get_activity_log list_activity_logs get_api_log list_api_logs
      get_coupon list_coupons list_applied_coupons
      get_event list_events
      get_credit_note list_credit_notes
      get_plan list_plans
      get_payment list_payments list_customer_payments
    ]
  end

  it "covers every tool of the MCP server" do
    expect(described_class::RULES.keys).to match_array(write_tools + read_tools)
  end

  it "asks for a confirmation before every write" do
    expect(described_class::RULES.select { |_, rule| rule.write? }.keys).to match_array(write_tools)
  end

  it "only uses permissions that exist" do
    permissions = described_class::RULES.values.flat_map(&:permissions).uniq

    expect(permissions - Permission.permissions_hash.keys).to be_empty
  end

  it "maps writes to the permission the dashboard checks" do
    expect(described_class.rule("create_coupon").permissions).to eq(%w[coupons:create])
    expect(described_class.rule("apply_coupon").permissions).to eq(%w[coupons:attach])
    expect(described_class.rule("void_invoice").permissions).to eq(%w[invoices:void])
    expect(described_class.rule("create_credit_note").permissions).to eq(%w[credit_notes:create])
    expect(described_class.rule("create_event").permissions).to eq(%w[developers:manage])
    expect(described_class.rule("create_customer").permissions).to eq(%w[customers:create customers:update])
  end

  it "does not know other tools" do
    expect(described_class.known?("drop_database")).to be(false)
    expect(described_class.rule("drop_database")).to be_nil
  end
end
