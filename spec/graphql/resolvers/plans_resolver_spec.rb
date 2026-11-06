# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::PlansResolver do
  let_it_be(:organization) { create_default(:organization) }
  let_it_be(:user) { create_default(:user) }
  let(:required_permission) { "plans:view" }
  let(:plan) { create(:plan, organization:) }
  let(:query) do
    <<~GQL
      query($withDeleted: Boolean) {
        plans(limit: 5, withDeleted: $withDeleted) {
          collection { id chargesCount customersCount }
          metadata { currentPage, totalCount }
        }
      }
    GQL
  end

  let_it_be(:membership) { create_default(:membership) }

  let_it_be(:organization) { membership.organization }
  let_it_be(:customer) { create_default(:customer, organization:) }

  before do
    plan
    customer

    2.times do
      create(:subscription, customer:, plan:)
    end
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "plans:view"

  it "returns a list of plans" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:
    )

    plans_response = result["data"]["plans"]

    expect(plans_response["collection"].count).to eq(organization.plans.count)
    expect(plans_response["collection"].first["id"]).to eq(plan.id)
    expect(plans_response["collection"].first["customersCount"]).to eq(1)

    expect(plans_response["metadata"]["currentPage"]).to eq(1)
    expect(plans_response["metadata"]["totalCount"]).to eq(1)
  end

  context "with every count field on several plans" do
    let(:counts_query) do
      <<~GQL
        query {
          plans(limit: 5) {
            collection {
              id
              activeSubscriptionsCount
              chargesCount
              customersCount
              draftInvoicesCount
              fixedChargesCount
              subscriptionsCount
            }
          }
        }
      GQL
    end
    let(:overridden_plan) { create(:plan, organization:, parent: plan) }
    let(:other_plans) { create_list(:plan, 2, organization:) }

    before do
      create_list(:standard_charge, 2, plan:, organization:)
      create(:fixed_charge, plan:, organization:)
      subscription = create(:subscription, customer:, plan: overridden_plan)
      create(:subscription, :terminated, customer:, plan:)
      create(:invoice_subscription, subscription:, invoice: create(:invoice, :draft, customer:, organization:))
      other_plans.each { create(:subscription, customer:, plan: it) }
    end

    it "returns the counts with one query per count, whatever the number of plans" do
      count_queries = []
      callback = ->(*, payload) { count_queries << payload[:sql] if payload[:sql].start_with?("SELECT COUNT") }

      result = ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
        execute_graphql(current_user: membership.user, current_organization: organization, permissions: required_permission, query: counts_query)
      end

      collection = result["data"]["plans"]["collection"].index_by { it["id"] }
      expect(collection[plan.id]).to eq(
        "id" => plan.id,
        "activeSubscriptionsCount" => 3,
        "chargesCount" => 2,
        "customersCount" => 1,
        "draftInvoicesCount" => 1,
        "fixedChargesCount" => 1,
        "subscriptionsCount" => 4
      )
      expect(collection[other_plans.first.id]).to include("activeSubscriptionsCount" => 1, "chargesCount" => 0, "draftInvoicesCount" => 0)
      expect(count_queries.size).to eq(6)
    end
  end

  context "when filtering by with_deleted" do
    let(:plan) { create(:plan, organization:) }
    let(:deleted_plan) { create(:plan, organization:, deleted_at: Time.current) }

    before do
      plan
      deleted_plan
    end

    it "returns all plans including deleted ones" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:,
        variables: {withDeleted: true}
      )

      plans_response = result["data"]["plans"]
      expect(plans_response["collection"].count).to eq(2)
      expect(plans_response["collection"].map { |p| p["id"] }).to include(plan.id, deleted_plan.id)

      expect(plans_response["metadata"]["currentPage"]).to eq(1)
      expect(plans_response["metadata"]["totalCount"]).to eq(2)
    end
  end
end
