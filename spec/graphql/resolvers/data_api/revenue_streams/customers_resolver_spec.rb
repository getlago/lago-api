# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::DataApi::RevenueStreams::CustomersResolver, type: :graphql do
  let(:required_permission) { "data_api:revenue_streams:view" }
  let(:query) do
    <<~GQL
      query($currency: CurrencyEnum, $orderBy: OrderByEnum, $limit: Int, $offset: Int) {
        revenueStreamsCustomers(currency: $currency, orderBy: $orderBy, limit: $limit, offset: $offset) {
          collection {
            customerId
            externalCustomerId
            customerName
            amountCurrency
            grossRevenueAmountCents
            grossRevenueShare
            netRevenueAmountCents
            netRevenueShare
          }
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:body_response) { File.read("spec/fixtures/lago_data_api/revenue_streams_customers.json") }

  around { |test| lago_premium!(&test) }

  before do
    stub_request(:get, "#{ENV["LAGO_DATA_API_URL"]}/revenue_streams/#{organization.id}/customers")
      .to_return(status: 200, body: body_response, headers: {})
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "data_api:revenue_streams:view"

  it "returns a list of revenue streams customers" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:
    )

    revenue_streams_response = result["data"]["revenueStreamsCustomers"]
    expect(revenue_streams_response["collection"].first).to include(
      {
        "amountCurrency" => "EUR",
        "customerId" => "e4676e50-1234-4606-bcdb-42effbc2b635",
        "externalCustomerId" => "2537afc4-1234-4abb-89b7-d9b28c35780b",
        "customerName" => "Penny",
        "grossRevenueAmountCents" => "124628322",
        "netRevenueAmountCents" => "124628322",
        "grossRevenueShare" => 0.1185,
        "netRevenueShare" => 0.1185
      }
    )
  end
end
