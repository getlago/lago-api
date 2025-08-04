# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::DataApi::Usages::ForecastedResolver, type: :graphql do
  let(:required_permission) { "data_api:view" }
  let(:query) do
    <<~GQL
      query($currency: CurrencyEnum) {
        dataApiUsagesForecasted(currency: $currency) {
          collection {
            startOfPeriodDt
            endOfPeriodDt
            amountCents
            amountCurrency
            amountCentsForecast10thPercentile
            amountCentsForecast50thPercentile
            amountCentsForecast90thPercentile
            units
            unitsForecast10thPercentile
            unitsForecast50thPercentile
            unitsForecast90thPercentile
          }
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:body_response) { File.read("spec/fixtures/lago_data_api/usages_forecasted.json") }

  around { |test| lago_premium!(&test) }

  before do
    stub_request(:get, "#{ENV["LAGO_DATA_API_URL"]}/usages/#{organization.id}/forecasted/")
      .to_return(status: 200, body: body_response, headers: {})
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "data_api:view"

  it "returns a list of usages forecasted" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:
    )

    usages_forecasted_response = result["data"]["dataApiUsagesForecasted"]
    expect(usages_forecasted_response["collection"].first).to include(
      {
        "startOfPeriodDt" => "2025-06-23",
        "endOfPeriodDt" => "2025-06-23",
        "amountCurrency" => "EUR",
        "amountCents" => "1000"
      }
    )
  end
end
