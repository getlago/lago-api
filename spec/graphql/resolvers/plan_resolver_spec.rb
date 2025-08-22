# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::PlanResolver, type: :graphql do
  subject(:result) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:,
      variables: {planId: plan.id}
    )
  end

  let(:required_permission) { "plans:view" }
  let(:query) do
    <<~GQL
      query($planId: ID!) {
        plan(id: $planId) {
          id
          name
          hasActiveSubscriptions
          hasCharges
          hasCustomers
          hasDraftInvoices
          hasFixedCharges
          hasOverriddenPlans
          hasSubscriptions

          customersCount
          subscriptionsCount
          activeSubscriptionsCount
          draftInvoicesCount

          taxes { id rate }
          charges {
            id
            taxes { id rate }
            properties {
              amount
              pricingGroupKeys
              freeUnits
              packageSize
              fixedAmount
              freeUnitsPerEvents
              freeUnitsPerTotalAggregation
              perTransactionMaxAmount
              perTransactionMinAmount
              rate
            }
          }
          fixedCharges {
            id
            taxes { id rate }
            properties { amount }
          }
          minimumCommitment {
            id
            amountCents
            invoiceDisplayName
            taxes { id rate }
          }
          entitlements { code name description privileges { code value name valueType } }
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }

  let(:add_on) { create(:add_on, organization:) }
  let(:billable_metric) { create(:billable_metric, organization:) }
  let(:minimum_commitment) { create(:commitment, :minimum_commitment, plan:) }

  before do
    customer
    minimum_commitment
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "plans:view"

  it "returns a single plan" do
    plan_response = result["data"]["plan"]

    expect(plan_response["id"]).to eq(plan.id)
    expect(plan_response["hasCharges"]).to eq(false)
    expect(plan_response["hasCustomers"]).to eq(false)
    expect(plan_response["hasDraftInvoices"]).to eq(false)
    expect(plan_response["hasFixedCharges"]).to eq(false)
    expect(plan_response["hasActiveSubscriptions"]).to eq(false)
    expect(plan_response["hasSubscriptions"]).to eq(false)

    expect(plan_response["minimumCommitment"]).to include(
      "id" => minimum_commitment.id,
      "amountCents" => minimum_commitment.amount_cents.to_s,
      "invoiceDisplayName" => minimum_commitment.invoice_display_name,
      "taxes" => []
    )
    expect(plan_response["entitlements"]).to be_empty
  end

  context "when plan has active subscriptions" do
    before do
      create_list(:subscription, 2, customer:, plan:)
    end

    it "returns true for has active subscriptions and subscriptions" do
      plan_response = result["data"]["plan"]

      expect(plan_response["hasCustomers"]).to eq(true)
      expect(plan_response["hasActiveSubscriptions"]).to eq(true)
      expect(plan_response["hasSubscriptions"]).to eq(true)

      expect(plan_response["customersCount"]).to eq(1)
      expect(plan_response["subscriptionsCount"]).to eq(2)
    end
  end

  context "when child plan has active subscriptions" do
    before do
      child_plan = create(:plan, organization:, parent: plan)
      create(:subscription, customer:, plan: child_plan)
    end

    it "returns true for has active subscriptions and subscriptions" do
      plan_response = result["data"]["plan"]

      expect(plan_response["hasCustomers"]).to eq(true)
      expect(plan_response["hasActiveSubscriptions"]).to eq(true)
      expect(plan_response["hasSubscriptions"]).to eq(true)

      expect(plan_response["customersCount"]).to eq(1)
      expect(plan_response["subscriptionsCount"]).to eq(1)
    end
  end

  context "when plan only has terminated subscriptions" do
    before do
      create(:subscription, :terminated, customer:, plan:)
    end

    it "returns true for has subscriptions but false for active subscriptions" do
      plan_response = result["data"]["plan"]

      expect(plan_response["hasCustomers"]).to eq(false)
      expect(plan_response["hasActiveSubscriptions"]).to eq(false)
      expect(plan_response["hasSubscriptions"]).to eq(true)

      expect(plan_response["customersCount"]).to eq(0)
      expect(plan_response["subscriptionsCount"]).to eq(1)
    end
  end

  context "when child plan has terminated subscriptions" do
    before do
      child_plan = create(:plan, organization:, parent: plan)
      create(:subscription, :terminated, customer:, plan: child_plan)
    end

    it "returns true for has subscriptions but false for active subscriptions" do
      plan_response = result["data"]["plan"]

      expect(plan_response["hasCustomers"]).to eq(false)
      expect(plan_response["hasActiveSubscriptions"]).to eq(false)
      expect(plan_response["hasSubscriptions"]).to eq(true)

      expect(plan_response["customersCount"]).to eq(0)
      expect(plan_response["subscriptionsCount"]).to eq(1)
    end
  end

  context "when plan has charges" do
    before do
      create(:standard_charge, billable_metric:, plan:)
    end

    it "returns true for has charges" do
      plan_response = result["data"]["plan"]

      expect(plan_response["hasCharges"]).to eq(true)
    end
  end

  context "when plan has fixed charges" do
    let(:fixed_charge) { create(:fixed_charge, add_on:, plan:) }

    before { fixed_charge }

    it "returns true for has charges" do
      plan_response = result["data"]["plan"]

      expect(plan_response["hasFixedCharges"]).to eq(true)
      expect(plan_response["fixedCharges"].pluck("id")).to match_array([fixed_charge.id])
    end
  end

  context "when plan has draft invoices" do
    before do
      subscription = create(:subscription, customer:, plan:)
      invoice = create(:invoice, :draft, customer:)
      create(:invoice_subscription, subscription:, invoice:)
    end

    it "returns true for has draft invoices" do
      plan_response = result["data"]["plan"]

      expect(plan_response["hasDraftInvoices"]).to eq(true)
    end
  end

  context "when child plan has draft invoices" do
    before do
      child_plan = create(:plan, organization:, parent: plan)
      subscription = create(:subscription, :terminated, customer:, plan: child_plan)
      invoice = create(:invoice, :draft, customer:)
      create(:invoice_subscription, subscription:, invoice:)
    end

    it "returns true for has draft invoices" do
      plan_response = result["data"]["plan"]

      expect(plan_response["hasDraftInvoices"]).to eq(true)
    end
  end

  context "when plan has entitlements" do
    before do
      feature = create(:feature, organization:, code: "seats")
      entitlement = create(:entitlement, plan:, feature:)
      create(:entitlement_value, entitlement:, privilege: create(:privilege, feature:, code: "max", value_type: "integer"), value: 10)

      feature2 = create(:feature, organization:, code: "storage")
      entitlement2 = create(:entitlement, plan:, feature: feature2, created_at: 1.day.ago)
      create(:entitlement_value, entitlement: entitlement2, privilege: create(:privilege, feature: feature2, code: "curr"), value: 2)
    end

    it "returns entitlements" do
      entitlements = result["data"]["plan"]["entitlements"]
      expect(entitlements.first["code"]).to eq "storage"
      expect(entitlements.first["privileges"].sole["value"]).to eq "2"
      expect(entitlements.second["code"]).to eq "seats"
      expect(entitlements.second["privileges"].sole["value"]).to eq "10"
    end

    context "when plan is an override" do
      subject(:result) do
        execute_graphql(
          current_user: membership.user,
          current_organization: organization,
          permissions: required_permission,
          query:,
          variables: {planId: child_plan.id}
        )
      end

      let(:child_plan) { create(:plan, organization:, parent: plan) }

      it "doesn't return entitlements to avoid confusion" do
        expect(result["data"]["plan"]["entitlements"]).to be_empty
      end
    end
  end

  context "when plan is not found" do
    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:,
        variables: {planId: "foo"}
      )

      expect_graphql_error(
        result:,
        message: "Resource not found"
      )
    end
  end
end
