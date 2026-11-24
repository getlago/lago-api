# frozen_string_literal: true

require "rails_helper"

RSpec.describe "exports_contracts view" do # rubocop:disable RSpec/DescribeClass
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:catalog_plan) { create(:catalog_plan, organization:) }
  let(:payment_method) { create(:payment_method, organization:, customer:) }

  let(:contract) do
    create(
      :contract,
      organization:,
      customer:,
      catalog_plan:,
      billing_entity: customer.billing_entity,
      payment_method:,
      name: "Enterprise contract",
      billing_anchor_date: Date.new(2026, 1, 15),
      ended_at: Time.zone.parse("2027-01-15T00:00:00Z"),
      purchase_order_number: "PO-123",
      consolidate_invoice: false,
      skip_invoice_custom_sections: true
    )
  end
  let(:terminated_contract) { create(:contract, :terminated, organization:, customer:, payment_method_type: :manual) }
  let(:canceled_contract) { create(:contract, :canceled, organization:, customer:) }

  let(:result) { ActiveRecord::Base.connection.select_all("SELECT * FROM exports_contracts") }

  def row_for(contract)
    result.to_a.find { |row| row["lago_id"] == contract.id }.symbolize_keys
  end

  before do
    contract
    terminated_contract
    canceled_contract
  end

  it "exposes the expected columns" do
    expect(result.columns).to eq(
      %w[
        organization_id
        lago_id
        lago_customer_id
        external_id
        code
        name
        status
        billing_anchor_date
        started_at
        ended_at
        terminated_at
        canceled_at
        lago_catalog_plan_id
        lago_billing_entity_id
        lago_payment_method_id
        payment_method_type
        purchase_order_number
        consolidate_invoice
        skip_invoice_custom_sections
        created_at
        updated_at
      ]
    )
  end

  it "exports the contract with its customer, plan, billing entity and payment method" do
    contract.reload

    expect(row_for(contract)).to eq(
      organization_id: organization.id,
      lago_id: contract.id,
      lago_customer_id: customer.id,
      external_id: contract.external_id,
      code: contract.code,
      name: "Enterprise contract",
      status: "active",
      billing_anchor_date: Date.new(2026, 1, 15),
      started_at: contract.started_at,
      ended_at: contract.ended_at,
      terminated_at: nil,
      canceled_at: nil,
      lago_catalog_plan_id: catalog_plan.id,
      lago_billing_entity_id: customer.billing_entity_id,
      lago_payment_method_id: payment_method.id,
      payment_method_type: "provider",
      purchase_order_number: "PO-123",
      consolidate_invoice: false,
      skip_invoice_custom_sections: true,
      created_at: contract.created_at,
      updated_at: contract.updated_at
    )
  end

  it "exports the status and payment method type as text" do
    expect(row_for(terminated_contract)).to include(
      status: "terminated",
      payment_method_type: "manual",
      terminated_at: terminated_contract.reload.terminated_at
    )
    expect(row_for(canceled_contract)).to include(
      status: "canceled",
      canceled_at: canceled_contract.reload.canceled_at
    )
  end
end
