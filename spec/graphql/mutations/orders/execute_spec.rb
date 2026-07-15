# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Orders::Execute do
  let(:required_permission) { "orders:execute" }
  let(:organization) { create(:organization, feature_flags: ["order_forms"]) }
  let(:membership) { create(:membership, organization:) }
  let(:customer) { create(:customer, organization:) }
  let(:quote) { create(:quote, organization:, customer:, order_type: :one_off) }
  let(:quote_version) { create(:quote_version, :approved, quote:, organization:) }
  let(:order_form) { create(:order_form, :signed, organization:, customer:, quote_version:) }
  let(:order) { create(:order, organization:, customer:, order_form:, execution_mode: :order_only) }

  let(:mutation) do
    <<~GQL
      mutation($input: ExecuteOrderInput!) {
        executeOrder(input: $input) {
          id
          status
          executedAt
        }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "orders:execute"

  it "executes the order", :premium do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query: mutation,
      variables: {input: {id: order.id}}
    )

    data = result["data"]["executeOrder"]

    expect(data["id"]).to eq(order.id)
    expect(data["status"]).to eq("executed")
    expect(data["executedAt"]).to be_present
  end

  context "without a premium license" do
    it "returns a forbidden error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query: mutation,
        variables: {input: {id: order.id}}
      )

      expect_graphql_error(result:, message: "feature_unavailable")
    end
  end

  context "when the execution fails", :premium do
    let(:order) { create(:order, organization:, customer:, order_form:, execution_mode: :execute_in_lago) }

    let(:failed_result) do
      Invoices::CreateOneOffService::Result.new.tap do |failed|
        failed.single_validation_failure!(field: :currency, error_code: "currencies_does_not_match")
      end
    end

    before do
      allow(Invoices::CreateOneOffService).to receive(:call!).and_raise(failed_result.error)
    end

    it "surfaces the error and marks the order failed" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query: mutation,
        variables: {input: {id: order.id}}
      )

      expect_unprocessable_entity(result, details: {currency: ["currencies_does_not_match"]})

      order.reload
      expect(order.failed?).to eq(true)
      expect(order.execution_record["errors"]).to eq(["currencies_does_not_match"])
    end
  end

  context "when order is not found" do
    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query: mutation,
        variables: {input: {id: SecureRandom.uuid}}
      )

      expect_graphql_error(result:, message: "Resource not found")
    end
  end
end
