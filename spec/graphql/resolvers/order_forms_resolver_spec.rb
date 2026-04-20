# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::OrderFormsResolver do
  let(:required_permission) { "order_forms:view" }
  let(:query) {}

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:quote) { create(:quote, organization:, customer:) }
  let!(:order_form) { create(:order_form, organization:, customer:, quote:) }

  before { create(:order_form, :signed, organization:, customer:, quote:) }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "order_forms:view"

  context "when listing all order forms" do
    let(:query) do
      <<~GQL
        query {
          orderForms(limit: 5) {
            collection {
              id
              number
              status
            }
            metadata { currentPage, totalCount }
          }
        }
      GQL
    end

    it "returns a list of order forms" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:
      )

      response = result["data"]["orderForms"]

      expect(response["collection"].count).to eq(2)
      expect(response["metadata"]["totalCount"]).to eq(2)
    end
  end

  context "when filtering by status" do
    let(:query) do
      <<~GQL
        query($status: [OrderFormStatusEnum!]) {
          orderForms(status: $status, limit: 5) {
            collection { id status }
            metadata { totalCount }
          }
        }
      GQL
    end

    it "returns only matching order forms" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:,
        variables: {status: ["generated"]}
      )

      response = result["data"]["orderForms"]

      expect(response["collection"].count).to eq(1)
      expect(response["collection"].first["id"]).to eq(order_form.id)
    end
  end

  context "when filtering by number" do
    let(:query) do
      <<~GQL
        query($number: [String!]) {
          orderForms(number: $number, limit: 5) {
            collection { id number }
            metadata { totalCount }
          }
        }
      GQL
    end

    it "returns only matching order forms" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:,
        variables: {number: [order_form.number]}
      )

      response = result["data"]["orderForms"]

      expect(response["collection"].count).to eq(1)
      expect(response["collection"].first["id"]).to eq(order_form.id)
    end
  end

  context "when filtering by customer_id" do
    let(:other_customer) { create(:customer, organization:) }
    let(:other_quote) { create(:quote, organization:, customer: other_customer) }

    let(:query) do
      <<~GQL
        query($customerId: [ID!]) {
          orderForms(customerId: $customerId, limit: 5) {
            collection { id }
            metadata { totalCount }
          }
        }
      GQL
    end

    before { create(:order_form, organization:, customer: other_customer, quote: other_quote) }

    it "returns only matching order forms" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:,
        variables: {customerId: [customer.id]}
      )

      response = result["data"]["orderForms"]

      expect(response["collection"].count).to eq(2)
      expect(response["metadata"]["totalCount"]).to eq(2)
    end
  end

  context "when filtering by quote_number" do
    let(:other_customer) { create(:customer, organization:) }
    let(:other_quote) { create(:quote, organization:, customer: other_customer) }

    let(:query) do
      <<~GQL
        query($quoteNumber: [String!]) {
          orderForms(quoteNumber: $quoteNumber, limit: 5) {
            collection { id }
            metadata { totalCount }
          }
        }
      GQL
    end

    before { create(:order_form, organization:, customer: other_customer, quote: other_quote) }

    it "returns only matching order forms" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:,
        variables: {quoteNumber: [quote.number]}
      )

      response = result["data"]["orderForms"]

      expect(response["collection"].count).to eq(2)
      expect(response["metadata"]["totalCount"]).to eq(2)
    end
  end

  context "when filtering by owner_id" do
    let(:query) do
      <<~GQL
        query($ownerId: [ID!]) {
          orderForms(ownerId: $ownerId, limit: 5) {
            collection { id }
            metadata { totalCount }
          }
        }
      GQL
    end

    before { QuoteOwner.create!(organization:, quote:, user: membership.user) }

    it "returns only matching order forms" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:,
        variables: {ownerId: [membership.user.id]}
      )

      response = result["data"]["orderForms"]

      expect(response["collection"].count).to eq(2)
      expect(response["metadata"]["totalCount"]).to eq(2)
    end
  end

  context "when filtering by created_at range" do
    let!(:order_form) { create(:order_form, organization:, customer:, quote:, created_at: 5.days.ago) }

    let(:query) do
      <<~GQL
        query($createdAtFrom: ISO8601DateTime, $createdAtTo: ISO8601DateTime) {
          orderForms(createdAtFrom: $createdAtFrom, createdAtTo: $createdAtTo, limit: 5) {
            collection { id }
            metadata { totalCount }
          }
        }
      GQL
    end

    it "returns only order forms within the date range" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:,
        variables: {createdAtFrom: 2.days.ago.iso8601, createdAtTo: 1.day.from_now.iso8601}
      )

      response = result["data"]["orderForms"]

      expect(response["collection"].count).to eq(1)
      expect(response["metadata"]["totalCount"]).to eq(1)
    end
  end

  context "when filtering by expires_at range" do
    let!(:order_form) { create(:order_form, organization:, customer:, quote:, expires_at: 5.days.from_now) }

    let(:query) do
      <<~GQL
        query($expiresAtFrom: ISO8601DateTime, $expiresAtTo: ISO8601DateTime) {
          orderForms(expiresAtFrom: $expiresAtFrom, expiresAtTo: $expiresAtTo, limit: 5) {
            collection { id }
            metadata { totalCount }
          }
        }
      GQL
    end

    before { create(:order_form, :signed, organization:, customer:, quote:, expires_at: 15.days.from_now) }

    it "returns only order forms expiring within the date range" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:,
        variables: {expiresAtFrom: 3.days.from_now.iso8601, expiresAtTo: 10.days.from_now.iso8601}
      )

      response = result["data"]["orderForms"]

      expect(response["collection"].count).to eq(1)
      expect(response["collection"].first["id"]).to eq(order_form.id)
    end
  end
end
