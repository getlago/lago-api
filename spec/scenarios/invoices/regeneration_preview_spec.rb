# frozen_string_literal: true

require "rails_helper"

describe "Invoice regeneration preview" do
  include GraphQLHelper

  let(:query) do
    <<~GQL
      query($id: ID!) {
        invoiceBuildRegenerationPreview(id: $id) {
          id
          taxesRate
          appliedTaxes {
            taxCode
            taxRate
            amountCents
          }
          fees {
            id
            taxesRate
            appliedTaxes {
              taxCode
              taxRate
              amountCents
            }
          }
        }
      }
    GQL
  end

  let(:membership) { create(:membership, organization:) }
  let(:organization) do
    create(
      :organization,
      country: "FR",
      webhook_url: nil,
      eu_tax_management: false,
      billing_entities: [create(:billing_entity, country: "FR")]
    )
  end
  let(:customer) { Customer.find_by!(external_id: "customer_fr") }
  let(:add_on) { create(:add_on, organization:, amount_cents: 10_000) }

  it "rebuilds applied taxes using the current customer taxes" do
    Organizations::UpdateService.call!(organization:, params: {eu_tax_management: true})

    mock_vies_check!("FR12345678901")
    create_or_update_customer(
      {
        external_id: "customer_fr",
        name: "Jean",
        country: "FR",
        zipcode: "75018",
        currency: "EUR",
        tax_identification_number: "FR12345678901"
      }
    )

    expect(customer.reload.pending_vies_check).to be_nil
    expect(customer.taxes.sole.code).to eq("lago_eu_fr_standard")
    expect(customer.taxes.sole.rate).to eq(20.0)

    create_one_off_invoice(customer, [add_on])

    invoice = customer.invoices.sole
    fee = invoice.fees.sole
    expect(invoice.applied_taxes.sole.tax_code).to eq("lago_eu_fr_standard")
    expect(invoice.taxes_rate).to eq(20.0)
    expect(fee.applied_taxes.sole.tax_code).to eq("lago_eu_fr_standard")
    expect(fee.taxes_rate).to eq(20.0)

    create_or_update_customer({external_id: customer.external_id, tax_identification_number: nil})

    mock_vies_check!("ES12345678Z")
    create_or_update_customer(
      {
        external_id: customer.external_id,
        country: "ES",
        zipcode: "28001",
        tax_identification_number: "ES12345678Z"
      }
    )

    expect(customer.reload.taxes.sole.code).to eq("lago_eu_reverse_charge")
    expect(customer.taxes.sole.rate).to eq(0.0)

    data = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: "invoices:view",
      query:,
      variables: {id: invoice.id}
    )["data"]["invoiceBuildRegenerationPreview"]
    preview_fee = data["fees"].sole

    expect(data["id"]).to eq(invoice.id)
    expect(data["appliedTaxes"].map { |tax| tax["taxCode"] }).to eq(["lago_eu_reverse_charge"])
    expect(data["taxesRate"]).to eq(0.0)
    expect(preview_fee["id"]).to eq(fee.id)
    expect(preview_fee["appliedTaxes"].map { |tax| tax["taxCode"] }).to eq(["lago_eu_reverse_charge"])
    expect(preview_fee["taxesRate"]).to eq(0.0)

    expect(invoice.reload.applied_taxes.sole.tax_code).to eq("lago_eu_fr_standard")
    expect(invoice.taxes_rate).to eq(20.0)
    expect(fee.reload.applied_taxes.sole.tax_code).to eq("lago_eu_fr_standard")
    expect(fee.taxes_rate).to eq(20.0)
  end

  context "when the charge price changed after the invoice was finalized" do
    let(:customer) { create(:customer, organization:, currency: "EUR") }
    let(:billable_metric) { create(:sum_billable_metric, :recurring, organization:, field_name: "item_id") }
    let(:plan) { create(:plan, organization:, interval: :monthly, amount_cents: 0, amount_currency: "EUR", pay_in_advance: false) }
    let(:charge) do
      create(
        :standard_charge,
        plan:,
        billable_metric:,
        prorated: true,
        pay_in_advance: false,
        properties: {amount: "0"}
      )
    end
    let(:query) do
      <<~GQL
        query($id: ID!) {
          invoiceBuildRegenerationPreview(id: $id) {
            id
            fees {
              id
              feeType
              units
              amountCents
              preciseUnitAmount
            }
          }
        }
      GQL
    end

    it "prices the charge fee with the current price, prorated over the fee period" do
      charge

      subscription = travel_to(Time.zone.parse("2024-09-30T10:00:00")) do
        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: "sub_#{SecureRandom.hex(4)}",
            plan_code: plan.code,
            billing_time: "calendar"
          }
        )
        subscription = customer.subscriptions.sole
        ingest_event(subscription, billable_metric, 1)
        subscription
      end

      invoice = travel_to(Time.zone.parse("2024-10-01T01:00:00")) do
        perform_billing
        subscription.invoices.sole
      end

      charge_fee = invoice.fees.charge.sole
      expect(invoice).to be_finalized
      expect(charge_fee.units).to eq(1)
      expect(charge_fee.amount_cents).to eq(0)

      travel_to(Time.zone.parse("2024-10-02T10:00:00")) do
        update_plan_charge(plan, charge.code, {properties: {amount: "2000"}})
        expect(charge.reload.properties["amount"]).to eq("2000")

        void_invoice(invoice)
        expect(invoice).to be_voided

        data = execute_graphql(
          current_user: membership.user,
          current_organization: organization,
          permissions: "invoices:view",
          query:,
          variables: {id: invoice.id}
        )["data"]["invoiceBuildRegenerationPreview"]
        preview_fee = data["fees"].find { |fee| fee["id"] == charge_fee.id }

        # 1 unit at 2,000 EUR prorated over 1 day of a 30-day month. Billing rounds the
        # 1/30 proration coefficient up to 0.03334, so 200_000 * 0.03334 = 6668 cents.
        expect(preview_fee["units"]).to eq(1.0)
        expect(preview_fee["amountCents"]).to eq("6668")
        expect(preview_fee["preciseUnitAmount"]).to be_within(0.01).of(66.68)
      end
    end
  end

  context "when the overridden charge price changed after the invoice was finalized", :premium do
    let(:customer) { create(:customer, organization:, currency: "EUR") }
    let(:billable_metric) { create(:sum_billable_metric, :recurring, organization:, field_name: "item_id") }
    let(:plan) { create(:plan, organization:, interval: :monthly, amount_cents: 0, amount_currency: "EUR", pay_in_advance: false) }
    let(:charge) do
      create(
        :standard_charge,
        plan:,
        billable_metric:,
        prorated: true,
        pay_in_advance: false,
        properties: {amount: "0"}
      )
    end
    let(:query) do
      <<~GQL
        query($id: ID!) {
          invoiceBuildRegenerationPreview(id: $id) {
            id
            fees {
              id
              invoiceDisplayName
              units
              amountCents
              preciseUnitAmount
              charge { id }
              chargeFilter { id }
              subscription { id }
            }
          }
        }
      GQL
    end
    let(:regenerate_mutation) do
      <<~GQL
        mutation($input: RegenerateInvoiceInput!) {
          regenerateFromVoided(input: $input) { id }
        }
      GQL
    end

    it "previews and regenerates the fee with the current overridden price" do
      charge

      subscription = travel_to(Time.zone.parse("2024-09-30T10:00:00")) do
        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: "sub_#{SecureRandom.hex(4)}",
            plan_code: plan.code,
            billing_time: "calendar",
            plan_overrides: {charges: [{id: charge.id, properties: {amount: "0"}}]}
          }
        )
        subscription = customer.subscriptions.sole
        ingest_event(subscription, billable_metric, 1)
        subscription
      end
      child_charge = subscription.plan.charges.sole
      expect(child_charge.parent_id).to eq(charge.id)

      invoice = travel_to(Time.zone.parse("2024-10-01T01:00:00")) do
        perform_billing
        subscription.invoices.sole
      end

      charge_fee = invoice.fees.charge.sole
      expect(charge_fee.charge_id).to eq(child_charge.id)
      expect(charge_fee.amount_cents).to eq(0)

      travel_to(Time.zone.parse("2024-10-02T10:00:00")) do
        update_subscription_charge(subscription, child_charge.code, {properties: {amount: "2000"}})
        expect(child_charge.reload.properties["amount"]).to eq("2000")
        expect(subscription.plan.charges.sole.id).to eq(child_charge.id)

        void_invoice(invoice)

        preview = execute_graphql(
          current_user: membership.user,
          current_organization: organization,
          permissions: "invoices:view",
          query:,
          variables: {id: invoice.id}
        )["data"]["invoiceBuildRegenerationPreview"]
        preview_fee = preview["fees"].find { |fee| fee["id"] == charge_fee.id }

        # 1 unit at 2,000 EUR prorated over 1 day of a 30-day month. Billing rounds the
        # 1/30 proration coefficient up to 0.03334, so 200_000 * 0.03334 = 6668 cents.
        expect(preview_fee["units"]).to eq(1.0)
        expect(preview_fee["amountCents"]).to eq("6668")
        expect(preview_fee["preciseUnitAmount"]).to be_within(0.01).of(66.68)

        # NOTE: lago-front sends every preview fee back with its units and preciseUnitAmount as unitAmountCents.
        fees_input = preview["fees"].map do |fee|
          {
            id: fee["id"],
            units: fee["units"],
            unitAmountCents: fee["preciseUnitAmount"],
            chargeId: fee.dig("charge", "id"),
            chargeFilterId: fee.dig("chargeFilter", "id"),
            subscriptionId: fee.dig("subscription", "id"),
            invoiceDisplayName: fee["invoiceDisplayName"]
          }
        end

        regenerated = execute_graphql(
          current_user: membership.user,
          current_organization: organization,
          permissions: "invoices:update",
          query: regenerate_mutation,
          variables: {input: {voidedInvoiceId: invoice.id, fees: fees_input}}
        )["data"]["regenerateFromVoided"]
        regenerated_fee = Invoice.find(regenerated["id"]).fees.charge.sole

        expect(regenerated_fee.amount_cents).to eq(6668)
        expect(regenerated_fee.units).to eq(1)
        expect(regenerated_fee.charge_id).to eq(charge_fee.charge_id)
      end
    end
  end

  context "when the first plan override is created after the invoice", :premium do
    let(:customer) { create(:customer, organization:, currency: "EUR") }
    let(:billable_metric) { create(:sum_billable_metric, :recurring, organization:, field_name: "item_id") }
    let(:plan) { create(:plan, organization:, interval: :monthly, amount_cents: 0, amount_currency: "EUR", pay_in_advance: false) }
    let(:charge) do
      create(
        :standard_charge,
        plan:,
        billable_metric:,
        prorated: true,
        pay_in_advance: false,
        properties: {amount: "0"}
      )
    end
    let(:query) do
      <<~GQL
        query($id: ID!) {
          invoiceBuildRegenerationPreview(id: $id) {
            id
            fees {
              id
              invoiceDisplayName
              units
              amountCents
              preciseUnitAmount
              charge { id }
              chargeFilter { id }
              subscription { id }
            }
          }
        }
      GQL
    end
    let(:regenerate_mutation) do
      <<~GQL
        mutation($input: RegenerateInvoiceInput!) {
          regenerateFromVoided(input: $input) { id }
        }
      GQL
    end
    let(:subscription) do
      charge

      travel_to(Time.zone.parse("2024-09-30T10:00:00")) do
        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: "sub_#{SecureRandom.hex(4)}",
            plan_code: plan.code,
            billing_time: "calendar"
          }
        )
        subscription = customer.subscriptions.sole
        ingest_event(subscription, billable_metric, 1)
        subscription
      end
    end
    let(:invoice) do
      subscription

      travel_to(Time.zone.parse("2024-10-01T01:00:00")) do
        perform_billing
        subscription.invoices.sole
      end
    end
    let(:charge_fee) { invoice.fees.charge.sole }

    before do
      expect(invoice).to be_finalized
      expect(charge_fee.charge_id).to eq(charge.id)
      expect(charge_fee.units).to eq(1)
      expect(charge_fee.amount_cents).to eq(0)

      travel_to(Time.zone.parse("2024-10-02T10:00:00")) do
        update_subscription(subscription, {plan_overrides: {charges: [{id: charge.id, properties: {amount: "2000"}}]}})
        expect(subscription.reload.plan.parent_id).to eq(plan.id)
        expect(subscription.plan.charges.sole).to have_attributes(parent_id: charge.id, properties: {"amount" => "2000"})
        expect(charge.reload.properties["amount"]).to eq("0")

        void_invoice(invoice)
        expect(invoice.reload).to be_voided
      end
    end

    def build_preview
      travel_to(Time.zone.parse("2024-10-02T10:00:00")) do
        execute_graphql(
          current_user: membership.user,
          current_organization: organization,
          permissions: "invoices:view",
          query:,
          variables: {id: invoice.id}
        )["data"]["invoiceBuildRegenerationPreview"]
      end
    end

    def regenerate(fees_input)
      travel_to(Time.zone.parse("2024-10-02T10:00:00")) do
        regenerated = execute_graphql(
          current_user: membership.user,
          current_organization: organization,
          permissions: "invoices:update",
          query: regenerate_mutation,
          variables: {input: {voidedInvoiceId: invoice.id, fees: fees_input}}
        )["data"]["regenerateFromVoided"]
        Invoice.find(regenerated["id"]).fees.charge.sole
      end
    end

    it "previews and regenerates the fee with the child charge price" do
      preview = build_preview
      preview_fee = preview["fees"].find { |fee| fee["id"] == charge_fee.id }

      # 1 unit at 2,000 EUR prorated over 1 day of a 30-day month. Billing rounds the
      # 1/30 proration coefficient up to 0.03334, so 200_000 * 0.03334 = 6668 cents.
      expect(preview_fee["units"]).to eq(1.0)
      expect(preview_fee["amountCents"]).to eq("6668")
      expect(preview_fee["preciseUnitAmount"]).to be_within(0.01).of(66.68)

      # NOTE: lago-front sends every preview fee back with its units and preciseUnitAmount as unitAmountCents.
      fees_input = preview["fees"].map do |fee|
        {
          id: fee["id"],
          units: fee["units"],
          unitAmountCents: fee["preciseUnitAmount"],
          chargeId: fee.dig("charge", "id"),
          chargeFilterId: fee.dig("chargeFilter", "id"),
          subscriptionId: fee.dig("subscription", "id"),
          invoiceDisplayName: fee["invoiceDisplayName"]
        }
      end
      regenerated_fee = regenerate(fees_input)

      expect(regenerated_fee.amount_cents).to eq(6668)
      expect(regenerated_fee.units).to eq(1)
      expect(regenerated_fee.charge_id).to eq(charge.id)
    end

    it "regenerates a fee sent with units only with the child charge price" do
      preview = build_preview

      fees_input = preview["fees"].map do |fee|
        {
          id: fee["id"],
          units: fee["units"],
          chargeId: fee.dig("charge", "id"),
          chargeFilterId: fee.dig("chargeFilter", "id"),
          subscriptionId: fee.dig("subscription", "id"),
          invoiceDisplayName: fee["invoiceDisplayName"]
        }
      end
      regenerated_fee = regenerate(fees_input)

      # The units-only path applies the child charge model to the units without proration:
      # 1 unit at 2,000 EUR.
      expect(regenerated_fee.amount_cents).to eq(200_000)
      expect(regenerated_fee.units).to eq(1)
      expect(regenerated_fee.charge_id).to eq(charge.id)
    end
  end
end
