# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Plans::Create, type: :graphql do
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:plan_tax) { create(:tax, organization:) }
  let(:charge_tax) { create(:tax, organization:) }
  let(:commitment_tax) { create(:tax, organization:) }
  let(:minimum_commitment_invoice_display_name) { "Minimum spending" }
  let(:minimum_commitment_amount_cents) { 100 }

  let(:mutation) do
    <<~GQL
      mutation($input: CreatePlanInput!) {
        createPlan(input: $input) {
          id,
          name,
          invoiceDisplayName,
          code,
          interval,
          payInAdvance,
          amountCents,
          amountCurrency,
          taxes { id code rate }
          minimumCommitment {
            id,
            amountCents,
            invoiceDisplayName,
            taxes { id code rate }
          }
          charges {
            id,
            chargeModel,
            billableMetric { id name code }
            taxes { id code rate }
            properties {
              amount,
              freeUnits,
              packageSize,
              rate,
              fixedAmount,
              freeUnitsPerEvents,
              freeUnitsPerTotalAggregation,
              graduatedRanges { fromValue, toValue }
              volumeRanges { fromValue, toValue }
              graduatedPercentageRanges { fromValue toValue }
              perTransactionMaxAmount
              perTransactionMinAmount
            }
            groupProperties {
              groupId,
              invoiceDisplayName,
              values {
                amount,
                freeUnits,
                packageSize,
                rate,
                fixedAmount,
                freeUnitsPerEvents,
                freeUnitsPerTotalAggregation,
                graduatedRanges { fromValue, toValue },
                volumeRanges { fromValue, toValue }
              }
            }
            filters {
              invoiceDisplayName
              values
              properties { amount }
            }
          }
        }
      }
    GQL
  end

  let(:billable_metrics) do
    create_list(:billable_metric, 6, organization:)
  end

  let(:first_group) { create(:group, billable_metric: billable_metrics[1]) }
  let(:second_group) { create(:group, billable_metric: billable_metrics[2]) }

  let(:billable_metric_filter) do
    create(
      :billable_metric_filter,
      billable_metric: billable_metrics[0],
      key: "payment_method",
      values: %w[card sepa]
    )
  end

  let(:tax) { create(:tax, organization:) }

  around { |test| lago_premium!(&test) }

  it "creates a plan" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: membership.organization,
      query: mutation,
      variables: {
        input: {
          name: "New Plan",
          invoiceDisplayName: "New Plan Invoice Name",
          code: "new_plan",
          interval: "monthly",
          payInAdvance: false,
          amountCents: 200,
          amountCurrency: "EUR",
          taxCodes: [plan_tax.code],
          minimumCommitment: {
            amountCents: minimum_commitment_amount_cents,
            invoiceDisplayName: minimum_commitment_invoice_display_name,
            taxCodes: [commitment_tax.code]
          },
          charges: [
            {
              billableMetricId: billable_metrics[0].id,
              chargeModel: "standard",
              properties: {amount: "100.00"},
              taxCodes: [charge_tax.code],
              filters: [
                {
                  invoiceDisplayName: "Payment Method",
                  properties: {amount: "100.00"},
                  values: {billable_metric_filter.key => %w[card sepa]}
                }
              ]
            },
            {
              billableMetricId: billable_metrics[1].id,
              chargeModel: "package",
              groupProperties: [
                {
                  groupId: first_group.id,
                  invoiceDisplayName: "Group 1 Invoice Name",
                  values: {
                    amount: "300.00",
                    freeUnits: 10,
                    packageSize: 10
                  }
                }
              ]
            },
            {
              billableMetricId: billable_metrics[2].id,
              chargeModel: "percentage",
              groupProperties: [
                {
                  groupId: second_group.id,
                  invoiceDisplayName: "Group 2 Invoice Name",
                  values: {
                    rate: "0.25",
                    fixedAmount: "2",
                    freeUnitsPerEvents: 5,
                    freeUnitsPerTotalAggregation: "50",
                    perTransactionMaxAmount: "20",
                    perTransactionMinAmount: "10"
                  }
                }
              ]
            },
            {
              billableMetricId: billable_metrics[3].id,
              chargeModel: "graduated",
              properties: {
                graduatedRanges: [
                  {
                    fromValue: 0,
                    toValue: 10,
                    perUnitAmount: "2.00",
                    flatAmount: "0"
                  },
                  {
                    fromValue: 11,
                    toValue: nil,
                    perUnitAmount: "3.00",
                    flatAmount: "3.00"
                  }
                ]
              }
            },
            {
              billableMetricId: billable_metrics[4].id,
              chargeModel: "volume",
              properties: {
                volumeRanges: [
                  {
                    fromValue: 0,
                    toValue: 10,
                    perUnitAmount: "2.00",
                    flatAmount: "0"
                  },
                  {
                    fromValue: 11,
                    toValue: nil,
                    perUnitAmount: "3.00",
                    flatAmount: "3.00"
                  }
                ]
              }
            },
            {
              billableMetricId: billable_metrics[5].id,
              chargeModel: "graduated_percentage",
              properties: {
                graduatedPercentageRanges: [
                  {
                    fromValue: 0,
                    toValue: 10,
                    flatAmount: "0",
                    rate: "2"
                  },
                  {
                    fromValue: 11,
                    toValue: nil,
                    flatAmount: "3.00",
                    rate: "3"
                  }
                ]
              }
            }
          ]
        }
      }
    )

    result_data = result["data"]["createPlan"]

    aggregate_failures do
      expect(result_data["id"]).to be_present
      expect(result_data["name"]).to eq("New Plan")
      expect(result_data["invoiceDisplayName"]).to eq("New Plan Invoice Name")
      expect(result_data["code"]).to eq("new_plan")
      expect(result_data["interval"]).to eq("monthly")
      expect(result_data["payInAdvance"]).to eq(false)
      expect(result_data["amountCents"]).to eq("200")
      expect(result_data["taxes"][0]["code"]).to eq(plan_tax.code)
      expect(result_data["charges"].count).to eq(6)

      standard_charge = result_data["charges"][0]
      expect(standard_charge["properties"]["amount"]).to eq("100.00")
      expect(standard_charge["chargeModel"]).to eq("standard")
      expect(standard_charge["taxes"].count).to eq(1)
      expect(standard_charge["taxes"].first["code"]).to eq(charge_tax.code)

      filter = standard_charge["filters"].first
      expect(filter["invoiceDisplayName"]).to eq("Payment Method")
      expect(filter["properties"]["amount"]).to eq("100.00")
      expect(filter["values"]).to eq("payment_method" => %w[card sepa])

      package_charge = result_data["charges"][1]
      expect(package_charge["chargeModel"]).to eq("package")
      group_properties = package_charge["groupProperties"][0]["values"]
      expect(group_properties["amount"]).to eq("300.00")
      expect(group_properties["freeUnits"]).to eq("10")
      expect(group_properties["packageSize"]).to eq("10")
      expect(package_charge["groupProperties"][0]["invoiceDisplayName"]).to eq("Group 1 Invoice Name")

      percentage_charge = result_data["charges"][2]
      expect(percentage_charge["chargeModel"]).to eq("percentage")
      group_properties = percentage_charge["groupProperties"][0]["values"]
      expect(group_properties["rate"]).to eq("0.25")
      expect(group_properties["fixedAmount"]).to eq("2")
      expect(group_properties["freeUnitsPerEvents"]).to eq("5")
      expect(group_properties["freeUnitsPerTotalAggregation"]).to eq("50")
      expect(package_charge["groupProperties"][0]["invoiceDisplayName"]).to eq("Group 1 Invoice Name")

      graduated_charge = result_data["charges"][3]
      expect(graduated_charge["chargeModel"]).to eq("graduated")
      expect(graduated_charge["properties"]["graduatedRanges"].count).to eq(2)

      volume_charge = result_data["charges"][4]
      expect(volume_charge["chargeModel"]).to eq("volume")
      expect(volume_charge["properties"]["volumeRanges"].count).to eq(2)

      graduated_percentage_charge = result_data["charges"][5]
      expect(graduated_percentage_charge["chargeModel"]).to eq("graduated_percentage")
      expect(graduated_percentage_charge["properties"]["graduatedPercentageRanges"].count).to eq(2)

      expect(result_data["minimumCommitment"]).to include(
        "invoiceDisplayName" => minimum_commitment_invoice_display_name,
        "amountCents" => minimum_commitment_amount_cents.to_s
      )
      expect(result_data["minimumCommitment"]["taxes"].count).to eq(1)
    end
  end

  context "without current user" do
    it "returns an error" do
      result = execute_graphql(
        current_organization: membership.organization,
        query: mutation,
        variables: {
          input: {
            name: "New Plan",
            code: "new_plan",
            interval: "monthly",
            payInAdvance: false,
            amountCents: 200,
            amountCurrency: "EUR",
            charges: []
          }
        }
      )

      expect_unauthorized_error(result)
    end
  end

  context "without current organization" do
    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        query: mutation,
        variables: {
          input: {
            name: "New Plan",
            code: "new_plan",
            interval: "monthly",
            payInAdvance: false,
            amountCents: 200,
            amountCurrency: "EUR",
            charges: []
          }
        }
      )

      expect_forbidden_error(result)
    end
  end
end
