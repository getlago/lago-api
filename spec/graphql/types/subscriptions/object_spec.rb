# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::Subscriptions::Object do
  subject { described_class }
  it do
    expect(subject).to have_field(:customer).of_type("Customer!")
    expect(subject).to have_field(:external_id).of_type("String!")
    expect(subject).to have_field(:id).of_type("ID!")
    expect(subject).to have_field(:plan).of_type("Plan!")

    expect(subject).to have_field(:name).of_type("String")
    expect(subject).to have_field(:next_name).of_type("String")
    expect(subject).to have_field(:period_end_date).of_type("ISO8601Date")
    expect(subject).to have_field(:status).of_type("StatusTypeEnum")

    expect(subject).to have_field(:billing_time).of_type("BillingTimeEnum")
    expect(subject).to have_field(:canceled_at).of_type("ISO8601DateTime")
    expect(subject).to have_field(:ending_at).of_type("ISO8601DateTime")
    expect(subject).to have_field(:started_at).of_type("ISO8601DateTime")
    expect(subject).to have_field(:subscription_at).of_type("ISO8601DateTime")
    expect(subject).to have_field(:terminated_at).of_type("ISO8601DateTime")
    expect(subject).to have_field(:on_termination_credit_note).of_type("OnTerminationCreditNoteEnum")
    expect(subject).to have_field(:on_termination_invoice).of_type("OnTerminationInvoiceEnum!")

    expect(subject).to have_field(:current_billing_period_started_at).of_type("ISO8601DateTime")
    expect(subject).to have_field(:current_billing_period_ending_at).of_type("ISO8601DateTime")

    expect(subject).to have_field(:created_at).of_type("ISO8601DateTime!")
    expect(subject).to have_field(:updated_at).of_type("ISO8601DateTime!")

    expect(subject).to have_field(:next_plan).of_type("Plan")
    expect(subject).to have_field(:next_subscription).of_type("Subscription")
    expect(subject).to have_field(:next_subscription_type).of_type("NextSubscriptionTypeEnum")
    expect(subject).to have_field(:next_subscription_at).of_type("ISO8601DateTime")

    expect(subject).to have_field(:activity_logs).of_type("[ActivityLog!]")
    expect(subject).to have_field(:fees).of_type("[Fee!]")

    expect(subject).to have_field(:lifetime_usage).of_type("SubscriptionLifetimeUsage")
  end

  context "with fixed_charges and overrides"
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
end
