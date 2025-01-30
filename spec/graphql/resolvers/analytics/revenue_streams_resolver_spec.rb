# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::Analytics::RevenueStreamsResolver, type: :graphql do
  let(:required_permission) { "analytics:view" }
  let(:query) do
    <<~GQL
      query($currency: CurrencyEnum, $externalCustomerId: String) {
        revenueStreams(currency: $currency, externalCustomerId: $externalCustomerId) {
          collection {
            currency
            couponsAmountCents
            grossRevenueAmountCents
            netRevenueAmountCents
            commitmentFeeAmountCents
            inAdvanceFeeAmountCents
            oneOffFeeAmountCents
            subscriptionFeeAmountCents
            usageBasedFeeAmountCents
            fromDate
            toDate
          }
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "analytics:view"

  context "without premium feature" do
    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:
      )

      expect_graphql_error(result:, message: "unauthorized")
    end
  end

  context "with premium feature" do
    around { |test| lago_premium!(&test) }

    context "without premium addon" do
      it "returns an error" do
        result = execute_graphql(
          current_user: membership.user,
          current_organization: organization,
          permissions: required_permission,
          query:
        )

        expect_graphql_error(result:, message: "unauthorized")
      end
    end

    context "with premium addon" do
      before { organization.update!(premium_integrations: ["analytics_revenue_streams"]) }

      it "returns a list of revenue streams" do
        result = execute_graphql(
          current_user: membership.user,
          current_organization: organization,
          permissions: required_permission,
          query:
        )

        revenue_streams_response = result["data"]["revenueStreams"]
        expect(revenue_streams_response["collection"].first["grossRevenueAmountCents"]).to eq("2015000")
      end
    end
  end
end
