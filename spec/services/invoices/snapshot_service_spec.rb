# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::SnapshotService do
  subject(:result) { described_class.call(invoice:, connections:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:invoice) { create(:invoice, customer:, organization:) }

  let(:payment_connection) { create(:stripe_customer, customer:, organization:) }
  let(:tax_connection) { create(:anrok_customer, customer:, organization:) }
  let(:accounting_connection) { create(:netsuite_customer, customer:, organization:) }
  let(:crm_connection) { create(:hubspot_customer, customer:, organization:) }

  let(:connections) do
    [
      routing("payment", payment_connection),
      routing("tax", tax_connection),
      routing("accounting", accounting_connection),
      routing("crm", crm_connection)
    ]
  end

  def routing(category, connection, behavior: "inherit")
    ConnectionResolvable::Routing.new(category:, behavior:, code: connection&.code, connection_id: connection&.id)
  end

  def snapshot
    invoice.invoice_connections.reload.to_h do |connection|
      [connection.category, connection.payment_provider_customer_id || connection.integration_customer_id]
    end
  end

  it "snapshots the connection of every category" do
    expect(result).to be_success
    expect(snapshot).to eq(
      "payment" => payment_connection.id,
      "tax" => tax_connection.id,
      "accounting" => accounting_connection.id,
      "crm" => crm_connection.id
    )
  end

  it "stores payment connections and integration connections in their own columns" do
    result

    expect(invoice.payment_connection).to have_attributes(
      organization_id: organization.id,
      payment_provider_customer_id: payment_connection.id,
      integration_customer_id: nil
    )
    expect(invoice.tax_connection).to have_attributes(
      organization_id: organization.id,
      payment_provider_customer_id: nil,
      integration_customer_id: tax_connection.id
    )
  end

  context "when a category is skipped" do
    let(:connections) do
      [
        routing("payment", payment_connection, behavior: "specific"),
        routing("tax", tax_connection),
        routing("accounting", accounting_connection),
        routing("crm", nil, behavior: "skip")
      ]
    end

    it "creates no row for it" do
      expect(result).to be_success
      expect(snapshot).to eq(
        "payment" => payment_connection.id,
        "tax" => tax_connection.id,
        "accounting" => accounting_connection.id
      )
    end
  end

  context "when no category resolves to a connection" do
    let(:connections) { %w[payment tax accounting crm].map { routing(it, nil) } }

    it "creates no connection" do
      expect(result).to be_success
      expect(invoice.invoice_connections.count).to eq(0)
    end
  end

  context "when connections are nil" do
    let(:connections) { nil }

    it "creates no connection" do
      expect(result).to be_success
      expect(invoice.invoice_connections.count).to eq(0)
    end
  end

  context "when connections are empty" do
    let(:connections) { [] }

    it "creates no connection" do
      expect(result).to be_success
      expect(invoice.invoice_connections.count).to eq(0)
    end
  end
end
