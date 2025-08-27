# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::Subscriptions::Object, type: :request do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:add_on) { create(:add_on, organization:) }
  let(:fixed_charge) { create(:fixed_charge, plan:, add_on:, organization:, units: 2) }
  let(:subscription) { create(:subscription, customer:, plan:) }
  let(:override) do
    create(:subscription_fixed_charge_units_override,
      subscription:,
      fixed_charge:,
      units: 5
    )
  end

  before do
    fixed_charge
    override
  end

  describe "plan field" do
    let(:query) do
      <<~GQL
        query {
          subscription(id: "#{subscription.id}") {
            id
            plan {
              id
              fixedCharges {
                id
                units
              }
            }
          }
        }
      GQL
    end

    it "shows overridden units for fixed charges" do
      result = execute_graphql_query(query)
      
      expect(result["errors"]).to be_nil
      
      subscription_data = result["data"]["subscription"]
      plan_data = subscription_data["plan"]
      fixed_charge_data = plan_data["fixedCharges"].first
      
      expect(fixed_charge_data["units"]).to eq("5")
    end
  end

  describe "when no overrides exist" do
    let(:subscription_without_overrides) { create(:subscription, customer:, plan:) }
    let(:query) do
      <<~GQL
        query {
          subscription(id: "#{subscription_without_overrides.id}") {
            id
            plan {
              id
              fixedCharges {
                id
                units
              }
            }
          }
        }
      GQL
    end

    it "shows default units for fixed charges" do
      result = execute_graphql_query(query)
      
      expect(result["errors"]).to be_nil
      
      subscription_data = result["data"]["subscription"]
      plan_data = subscription_data["plan"]
      fixed_charge_data = plan_data["fixedCharges"].first
      
      expect(fixed_charge_data["units"]).to eq("2")
    end
  end

  private

  def execute_graphql_query(query)
    post "/graphql", params: {query: query}
    JSON.parse(response.body)
  end
end
