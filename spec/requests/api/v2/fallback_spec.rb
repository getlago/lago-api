# frozen_string_literal: true

require "rails_helper"

# v1 controllers serve these routes, so with v1 timestamps.
RSpec.describe "API v2 fallback to v1", v2_timestamps: false do
  let(:organization) { create(:organization) }

  it "serves a v1-backed resource under /api/v2" do
    billable_metric = create(:billable_metric, organization:)

    get_with_token(organization, "/api/v2/billable_metrics")

    expect(response).to have_http_status(:success)
    expect(json[:billable_metrics].map { it[:lago_id] }).to include(billable_metric.id)
  end

  it "ignores expands, which only the native v2 controllers validate" do
    get_with_token(organization, "/api/v2/billable_metrics?expands[]=__nope__")

    expect(response).to have_http_status(:success)
  end

  it "renders the v1 error body, which only the native v2 controllers replace" do
    get_with_token(organization, "/api/v2/billable_metrics/unknown")

    expect(response).to be_not_found_error("billable_metric")
    expect(json).not_to have_key(:details)
  end
end
