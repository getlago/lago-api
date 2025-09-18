# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::InvoiceResolver do
  let(:required_permission) { "invoices:view" }
  let(:query) do
    <<~GQL
      query($id: ID!) {
        invoice(id: $id) {
          id
          number
          feesAmountCents
          couponsAmountCents
          creditNotesAmountCents
          prepaidCreditAmountCents
          refundableAmountCents
          creditableAmountCents
          paymentDisputeLosable
          paymentStatus
          status
          customer {
            id
            name
            deletedAt
          }
          appliedTaxes {
            taxCode
            taxName
            taxRate
            taxDescription
            amountCents
            amountCurrency
          }
          invoiceSubscriptions {
            fromDatetime
            toDatetime
            chargesFromDatetime
            chargesToDatetime
            subscription {
              id
            }
            fees {
              currency
              id
              itemType
              itemCode
              itemName
              charge { id billableMetric { code } }
              taxesRate
              taxesAmountCents
              trueUpFee { id }
              trueUpParentFee { id }
              units
              preciseUnitAmount
              chargeFilter { invoiceDisplayName values }
              appliedTaxes {
                taxCode
                taxName
                taxRate
                taxDescription
                amountCents
                amountCurrency
              }
            }
          }
          subscriptions {
            id
          }
          fees {
            id
            itemType
            itemCode
            itemName
            creditableAmountCents
            charge {
              id
              billableMetric {
                code
                filters { key values }
              }
              filters { invoiceDisplayName values }
            }
            pricingUnitUsage {
              id
              amountCents
              conversionRate
              preciseAmountCents
              shortName
              unitAmountCents
              pricingUnit {
                id
                code
                name
                shortName
              }
            }
            walletTransaction {
              name
              walletName
            }
          }
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:invoice_subscription) { create(:invoice_subscription, invoice:) }
  let(:invoice) { create(:invoice, customer:, organization:, fees_amount_cents: 10) }
  let(:subscription) { invoice_subscription.subscription }
  let(:fee) { create(:fee, subscription:, invoice:, amount_cents: 10) }

  before { fee and invoice }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "invoices:view"

  it "returns a single invoice" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:,
      variables: {
        id: invoice.id
      }
    )

    data = result["data"]["invoice"]

    aggregate_failures do
      expect(data["id"]).to eq(invoice.id)
      expect(data["number"]).to eq(invoice.number)
      expect(data["paymentStatus"]).to eq(invoice.payment_status)
      expect(data["paymentDisputeLosable"]).to eq(true)
      expect(data["status"]).to eq(invoice.status)
      expect(data["customer"]["id"]).to eq(customer.id)
      expect(data["customer"]["name"]).to eq(customer.name)
      expect(data["invoiceSubscriptions"][0]["subscription"]["id"]).to eq(subscription.id)
      expect(data["invoiceSubscriptions"][0]["fees"][0]["id"]).to eq(fee.id)
    end
  end

  it "includes filters for each fee" do
    billable_metric_filter = create(:billable_metric_filter, key: "cloud", values: %w[aws gcp])
    charge_filter = create(:charge_filter, invoice_display_name: nil)
    charge_filter_value = create(:charge_filter_value, billable_metric_filter:, charge_filter:, values: ["aws"])

    fee.update!(charge_filter_id: charge_filter.id)

    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:,
      variables: {id: invoice.id}
    )

    fee = result["data"]["invoice"]["invoiceSubscriptions"][0]["fees"][0]
    expect(fee["chargeFilter"]["values"][billable_metric_filter.key]).to eq(charge_filter_value.values)
  end

  it "includes pricing unit usage when available" do
    pricing_unit = create(:pricing_unit, organization:)
    billable_metric = create(:billable_metric, organization:)
    charge = create(:standard_charge, billable_metric:)
    applied_pricing_unit = create(:applied_pricing_unit, pricing_unit:, conversion_rate: 2.5)

    pricing_unit_usage = build(
      :pricing_unit_usage,
      pricing_unit:,
      organization:,
      short_name: pricing_unit.short_name,
      conversion_rate: applied_pricing_unit.conversion_rate,
      amount_cents: 40,
      precise_amount_cents: 40.0,
      unit_amount_cents: 20
    )

    fee_with_usage = create(:fee, subscription:, invoice:, charge:, amount_cents: 100, organization:, pricing_unit_usage:)

    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:,
      variables: {id: invoice.id}
    )

    fees = result["data"]["invoice"]["fees"]
    fee_data = fees.find { |f| f["id"] == fee_with_usage.id }

    expect(fee_data["pricingUnitUsage"]).to be_present
    expect(fee_data["pricingUnitUsage"]["amountCents"]).to eq(pricing_unit_usage.amount_cents.to_s)
    expect(fee_data["pricingUnitUsage"]["preciseAmountCents"]).to eq(pricing_unit_usage.precise_amount_cents)
    expect(fee_data["pricingUnitUsage"]["unitAmountCents"]).to eq(pricing_unit_usage.unit_amount_cents.to_s)
    expect(fee_data["pricingUnitUsage"]["conversionRate"]).to eq(pricing_unit_usage.conversion_rate)
    expect(fee_data["pricingUnitUsage"]["shortName"]).to eq(pricing_unit_usage.short_name)
    expect(fee_data["pricingUnitUsage"]["pricingUnit"]["code"]).to eq(pricing_unit.code)
    expect(fee_data["pricingUnitUsage"]["pricingUnit"]["name"]).to eq(pricing_unit.name)
  end

  context "when invoice is not found" do
    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: invoice.organization,
        permissions: required_permission,
        query:,
        variables: {
          id: "foo"
        }
      )

      expect_graphql_error(result:, message: "Resource not found")
    end
  end

  context "with a deleted billable metric" do
    let(:billable_metric) { create(:billable_metric, :deleted) }
    let(:billable_metric_filter) { create(:billable_metric_filter, :deleted, billable_metric:) }
    let(:charge_filter) do
      create(:charge_filter, :deleted, charge:, properties: {amount: "10"})
    end
    let(:charge_filter_value) do
      create(
        :charge_filter_value,
        :deleted,
        charge_filter:,
        billable_metric_filter:,
        values: [billable_metric_filter.values.first]
      )
    end
    let(:fee) { create(:charge_fee, subscription:, invoice:, charge_filter:, charge:, amount_cents: 10) }

    let(:charge) do
      create(:standard_charge, :deleted, billable_metric:)
    end

    it "returns the invoice with the deleted resources" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:,
        variables: {
          id: invoice.id
        }
      )

      data = result["data"]["invoice"]

      aggregate_failures do
        expect(data["id"]).to eq(invoice.id)
        expect(data["number"]).to eq(invoice.number)
        expect(data["paymentStatus"]).to eq(invoice.payment_status)
        expect(data["status"]).to eq(invoice.status)
        expect(data["customer"]["id"]).to eq(customer.id)
        expect(data["customer"]["name"]).to eq(customer.name)
        expect(data["invoiceSubscriptions"][0]["subscription"]["id"]).to eq(subscription.id)
        expect(data["invoiceSubscriptions"][0]["fees"][0]["id"]).to eq(fee.id)
      end
    end
  end

  context "with an add on invoice" do
    let(:invoice) { create(:invoice, customer:, organization:, fees_amount_cents: 10) }
    let(:add_on) { create(:add_on, organization:) }
    let(:applied_add_on) { create(:applied_add_on, add_on:, customer:) }
    let(:fee) { create(:add_on_fee, invoice:, applied_add_on:) }

    it "returns a single invoice" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:,
        variables: {
          id: invoice.id
        }
      )

      data = result["data"]["invoice"]

      aggregate_failures do
        expect(data["id"]).to eq(invoice.id)
        expect(data["number"]).to eq(invoice.number)
        expect(data["paymentStatus"]).to eq(invoice.payment_status)
        expect(data["status"]).to eq(invoice.status)
        expect(data["customer"]["id"]).to eq(customer.id)
        expect(data["customer"]["name"]).to eq(customer.name)
        expect(data["fees"].first).to include(
          "itemCode" => add_on.code,
          "itemName" => add_on.name
        )
      end
    end

    context "with a deleted add_on" do
      let(:add_on) { create(:add_on, :deleted, organization:) }

      it "returns the invoice with the deleted resources" do
        result = execute_graphql(
          current_user: membership.user,
          current_organization: organization,
          permissions: required_permission,
          query:,
          variables: {
            id: invoice.id
          }
        )

        data = result["data"]["invoice"]

        aggregate_failures do
          expect(data["id"]).to eq(invoice.id)
          expect(data["number"]).to eq(invoice.number)
          expect(data["paymentStatus"]).to eq(invoice.payment_status)
          expect(data["status"]).to eq(invoice.status)
          expect(data["customer"]["id"]).to eq(customer.id)
          expect(data["customer"]["name"]).to eq(customer.name)
          expect(data["fees"].first).to include(
            "itemType" => "add_on",
            "itemCode" => add_on.code,
            "itemName" => add_on.name
          )
        end
      end
    end
  end

  context "with a deleted customer" do
    let(:customer) { create(:customer, :deleted, organization:) }

    it "returns the invoice with the deleted customer" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:,
        variables: {
          id: invoice.id
        }
      )

      data = result["data"]["invoice"]

      aggregate_failures do
        expect(data["id"]).to eq(invoice.id)
        expect(data["number"]).to eq(invoice.number)
        expect(data["paymentStatus"]).to eq(invoice.payment_status)
        expect(data["status"]).to eq(invoice.status)
        expect(data["customer"]["id"]).to eq(customer.id)
        expect(data["customer"]["name"]).to eq(customer.name)
        expect(data["customer"]["deletedAt"]).to eq(customer.deleted_at.iso8601)
      end
    end
  end

  context "with a credit invoice" do
    let(:invoice) { create(:invoice, :credit, customer:, organization:) }
    let(:fee) { create(:credit_fee, invoice:, invoiceable: wallet_transaction) }
    let(:wallet_transaction) { create(:wallet_transaction, organization:, wallet:) }
    let(:wallet) { create(:wallet, organization:, name: "wallet name") }

    before { fee }

    it "returns the invoice with the credit invoice" do
      result = execute_query(query:, variables: {id: invoice.id})

      data = result["data"]["invoice"]
      graphql_wallet_transaction = data.dig("fees", 0, "walletTransaction")
      expect(graphql_wallet_transaction["name"]).to eq("Custom Transaction Name")
      expect(graphql_wallet_transaction["walletName"]).to eq("wallet name")
    end
  end
end
