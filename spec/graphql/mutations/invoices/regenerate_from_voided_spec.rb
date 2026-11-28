# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Invoices::RegenerateFromVoided do
  let(:required_permission) { "invoices:update" }
  let(:voided_invoice) do
    create(
      :invoice,
      :voided,
      :with_subscriptions,
      organization:,
      customer:,
      subscriptions: [subscription],
      currency: "EUR"
    )
  end
  let(:subscription) do
    create(
      :subscription,
      plan:,
      subscription_at: started_at,
      started_at:,
      created_at: started_at
    )
  end
  let(:timestamp) { Time.zone.now - 1.year }
  let(:started_at) { Time.zone.now - 2.years }
  let(:fee_subscription) do
    create(
      :fee,
      invoice: voided_invoice,
      subscription:,
      fee_type: :subscription,
      amount_cents: 2_000
    )
  end
  let(:mutation) do
    <<~GQL
      mutation($input: RegenerateInvoiceInput!) {
        regenerateFromVoided(input: $input) {
          id
          voidedInvoiceId
          purchaseOrderNumber
          fees {
            id
            invoiceDisplayName
            units
            preciseUnitAmount
          }
          status
        }
      }
    GQL
  end
  let(:fee_input) do
    {
      id: fee_subscription.id,
      chargeId: fee_subscription.charge_id,
      subscriptionId: fee_subscription.subscription_id,
      invoiceDisplayName: "Adjusted",
      units: 2,
      unitAmountCents: 5000
    }
  end

  let_it_be(:organization) { create_default(:organization) }
  let_it_be(:user) { create_default(:user) }
  let_it_be(:membership) { create_default(:membership) }
  let_it_be(:customer) { create_default(:customer, organization:) }

  let_it_be(:plan) { create_default(:plan, organization:, interval: "monthly") }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "invoices:update"

  it "regenerates an invoice from a voided invoice" do
    freeze_time do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query: mutation,
        variables: {
          input: {
            voidedInvoiceId: voided_invoice.id,
            fees: [fee_input]
          }
        }
      )

      result_data = result.dig("data", "regenerateFromVoided")
      expect(result_data["id"]).to be_present
      expect(result_data["id"]).not_to eq(voided_invoice.id)
      expect(result_data["voidedInvoiceId"]).to eq(voided_invoice.id.to_s)
      expect(result_data["fees"].first["invoiceDisplayName"]).to eq(fee_input[:invoiceDisplayName])
      expect(result_data["fees"].first["units"]).to eq(fee_input[:units])
      expect(result_data["fees"].first["preciseUnitAmount"]).to eq(fee_input[:unitAmountCents])
      expect(result_data["status"]).to eq("finalized")
    end
  end

  it "produces an activity log" do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query: mutation,
      variables: {input: {voidedInvoiceId: voided_invoice.id, fees: [fee_input]}}
    )

    expect(Utils::ActivityLog).to have_produced("invoice.regenerated").after_commit.with(voided_invoice)
  end

  context "when a purchaseOrderNumber is provided" do
    it "stores the normalized value on the regenerated invoice" do
      freeze_time do
        result = execute_graphql(
          current_user: membership.user,
          current_organization: organization,
          permissions: required_permission,
          query: mutation,
          variables: {
            input: {
              voidedInvoiceId: voided_invoice.id,
              fees: [fee_input],
              purchaseOrderNumber: "  PO-EDITED  "
            }
          }
        )

        result_data = result.dig("data", "regenerateFromVoided")
        expect(result_data["purchaseOrderNumber"]).to eq("PO-EDITED")
      end
    end
  end

  context "when purchaseOrderNumber is not provided" do
    before { voided_invoice.update!(purchase_order_number: "PO-INHERIT") }

    it "inherits the purchase order number from the voided invoice" do
      freeze_time do
        result = execute_graphql(
          current_user: membership.user,
          current_organization: organization,
          permissions: required_permission,
          query: mutation,
          variables: {
            input: {
              voidedInvoiceId: voided_invoice.id,
              fees: [fee_input]
            }
          }
        )

        result_data = result.dig("data", "regenerateFromVoided")
        expect(result_data["purchaseOrderNumber"]).to eq("PO-INHERIT")
      end
    end
  end

  context "when the voided invoice is an advance_charges invoice" do
    let(:customer) { create(:customer, organization:, payment_provider: "stripe") }
    let(:advance_charges_plan) { create(:plan, organization:, interval: "monthly") }
    let(:subscription) do
      create(
        :subscription,
        customer:,
        plan: advance_charges_plan,
        subscription_at: started_at,
        started_at:,
        created_at: started_at
      )
    end
    let(:charge) do
      create(:standard_charge, plan: advance_charges_plan, pay_in_advance: true, invoiceable: false, properties: {amount: "10"})
    end
    let(:voided_invoice) do
      create(
        :invoice,
        :voided,
        :with_subscriptions,
        organization:,
        customer:,
        subscriptions: [subscription],
        currency: "EUR",
        invoice_type: :advance_charges,
        payment_status: :succeeded,
        fees_amount_cents: 1_000,
        sub_total_excluding_taxes_amount_cents: 1_000,
        taxes_amount_cents: 200,
        sub_total_including_taxes_amount_cents: 1_200,
        total_amount_cents: 1_200
      )
    end
    let(:charge_fee) do
      create(
        :charge_fee,
        invoice: voided_invoice,
        subscription:,
        charge:,
        units: 1,
        unit_amount_cents: 1_000,
        precise_unit_amount: 10,
        amount_cents: 1_000,
        precise_amount_cents: 1_000,
        taxes_amount_cents: 200,
        taxes_precise_amount_cents: 200,
        taxes_rate: 20,
        payment_status: :succeeded
      )
    end
    let(:fee_input) do
      {
        id: charge_fee.id,
        chargeId: charge.id,
        subscriptionId: subscription.id,
        invoiceDisplayName: charge_fee.invoice_display_name,
        units: 1,
        unitAmountCents: 10
      }
    end

    before do
      create(:customer_applied_tax, customer:, tax: create(:tax, organization:, rate: 8.5))
    end

    it "regenerates the advance_charges invoice with the current taxes and charges the payment provider" do
      freeze_time do
        result = execute_graphql(
          current_user: membership.user,
          current_organization: organization,
          permissions: required_permission,
          query: mutation,
          variables: {input: {voidedInvoiceId: voided_invoice.id, fees: [fee_input]}}
        )

        regenerated_invoice = Invoice.find(result.dig("data", "regenerateFromVoided", "id"))
        expect(regenerated_invoice).to have_attributes(
          invoice_type: "advance_charges",
          fees_amount_cents: 1_000,
          taxes_amount_cents: 85, # 1000 * 8.5%
          total_amount_cents: 1_085, # 1000 + 85
          payment_status: "pending"
        )
        expect(Invoices::Payments::CreateJob).to have_been_enqueued
          .with(invoice: regenerated_invoice, payment_provider: :stripe, payment_method_params: {})
        expect(Payments::ManualCreateJob).not_to have_been_enqueued
      end
    end
  end
end
