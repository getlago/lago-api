# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::OrderForms::Void do
  let(:required_permission) { "order_forms:void" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:quote) { create(:quote, organization:, customer:) }
  let(:order_form) { create(:order_form, organization:, customer:, quote:) }

  let(:mutation) do
    <<~GQL
      mutation($input: VoidOrderFormInput!) {
        voidOrderForm(input: $input) {
          id
          status
          voidReason
        }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "order_forms:void"

  it "voids the order form" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query: mutation,
      variables: {input: {id: order_form.id}}
    )

    data = result["data"]["voidOrderForm"]

    expect(data["id"]).to eq(order_form.id)
    expect(data["status"]).to eq("voided")
    expect(data["voidReason"]).to eq("manual")
  end

  context "when order form is not voidable" do
    let(:order_form) { create(:order_form, :signed, organization:, customer:, quote:) }

    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query: mutation,
        variables: {input: {id: order_form.id}}
      )

      expect_graphql_error(result:, message: "Method Not Allowed")
    end
  end

  context "when order form is not found" do
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
