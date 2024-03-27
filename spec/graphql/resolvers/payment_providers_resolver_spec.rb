# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::PaymentProvidersResolver, type: :graphql do
  let(:query) do
    <<~GQL
      query {
        paymentProviders(limit: 5) {
          collection {
            ... on AdyenProvider {
              id
              code
              __typename
            }
            ... on GocardlessProvider {
              id
              code
              __typename
            }
            ... on StripeProvider {
              id
              code
              __typename
            }
          }
          metadata { currentPage, totalCount }
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:adyen_provider) { create(:adyen_provider, organization:) }
  let(:gocardless_provider) { create(:gocardless_provider, organization:) }
  let(:stripe_provider) { create(:stripe_provider, organization:) }

  before do
    adyen_provider
    gocardless_provider
    stripe_provider
  end

  context "when type is present" do
    let(:query) do
      <<~GQL
        query {
          paymentProviders(limit: 5, type: stripe) {
            collection {
              ... on AdyenProvider {
                id
                code
                __typename
              }
              ... on GocardlessProvider {
                id
                code
                __typename
              }
              ... on StripeProvider {
                id
                code
                __typename
              }
            }
            metadata { currentPage, totalCount }
          }
        }
      GQL
    end

    it "returns a list of payment providers" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        query:
      )

      payment_providers_response = result["data"]["paymentProviders"]

      aggregate_failures do
        expect(payment_providers_response["collection"].count).to eq(1)
        expect(payment_providers_response["collection"].first["id"]).to eq(stripe_provider.id)

        expect(payment_providers_response["metadata"]["currentPage"]).to eq(1)
        expect(payment_providers_response["metadata"]["totalCount"]).to eq(1)
      end
    end
  end

  context "when type is not present" do
    it "returns a list of payment providers" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        query:
      )

      payment_providers_response = result["data"]["paymentProviders"]

      adyen_provider_result = payment_providers_response["collection"].find do |record|
        record["__typename"] == "AdyenProvider"
      end
      gocardless_provider_result = payment_providers_response["collection"].find do |record|
        record["__typename"] == "GocardlessProvider"
      end
      stripe_provider_result = payment_providers_response["collection"].find do |record|
        record["__typename"] == "StripeProvider"
      end

      aggregate_failures do
        expect(payment_providers_response["collection"].count).to eq(3)

        expect(adyen_provider_result["id"]).to eq(adyen_provider.id)
        expect(gocardless_provider_result["id"]).to eq(gocardless_provider.id)
        expect(stripe_provider_result["id"]).to eq(stripe_provider.id)

        expect(payment_providers_response["metadata"]["currentPage"]).to eq(1)
        expect(payment_providers_response["metadata"]["totalCount"]).to eq(3)
      end
    end
  end

  context "without current organization" do
    it "returns an error" do
      result = execute_graphql(current_user: membership.user, query:)

      expect_graphql_error(result:, message: "Missing organization id")
    end
  end

  context "when not member of the organization" do
    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: create(:organization),
        query:
      )

      expect_graphql_error(result:, message: "Not in organization")
    end
  end
end
