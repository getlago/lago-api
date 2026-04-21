# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Quotes::Void do
  let(:required_permission) { "quotes:void" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:quote) { create(:quote, organization:, customer:, status: :approved) }

  let(:mutation) do
    <<~GQL
      mutation($input: VoidQuoteInput!) {
        voidQuote(input: $input) {
          id
          status
          voidReason
          voidedAt
        }
      }
    GQL
  end

  before { organization.enable_feature_flag!(:quote) }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "quotes:void"

  it "voids the given quote", :premium do
    freeze_time do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query: mutation,
        variables: {
          input: {id: quote.id, reason: "manual"}
        }
      )

      result_data = result["data"]["voidQuote"]

      expect(result_data["id"]).to eq(quote.id)
      expect(result_data["status"]).to eq("voided")
      expect(result_data["voidReason"]).to eq("manual")
      expect(result_data["voidedAt"]).to eq(Time.current.iso8601)
    end
  end

  context "when the quote belongs to another organization", :premium do
    let(:other_organization) { create(:organization, feature_flags: ["quote"]) }
    let(:other_customer) { create(:customer, organization: other_organization) }
    let(:foreign_quote) { create(:quote, organization: other_organization, customer: other_customer, status: :approved) }

    it "returns a GraphQL error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query: mutation,
        variables: {
          input: {id: foreign_quote.id, reason: "manual"}
        }
      )

      expect(result["errors"]).to be_present
      expect(result["errors"].first["extensions"]["code"]).to eq("not_found")
      expect(result["errors"].first["extensions"]["details"]["quote"]).to eq(["not_found"])
    end
  end

  context "when the quote is already voided", :premium do
    let(:quote) { create(:quote, organization:, customer:, status: :voided, void_reason: "manual", voided_at: 1.day.ago) }

    it "returns an inappropriate_state error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query: mutation,
        variables: {
          input: {id: quote.id, reason: "manual"}
        }
      )

      expect(result["errors"]).to be_present
      expect(result["errors"].first["extensions"]["code"]).to eq("inappropriate_state")
    end
  end
end
