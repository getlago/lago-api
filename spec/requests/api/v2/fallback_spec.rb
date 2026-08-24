# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API v2 fallback to v1" do
  let(:organization) { create(:organization) }

  it "serves a v1-backed resource under /api/v2" do
    billable_metric = create(:billable_metric, organization:)

    get_with_token(organization, "/api/v2/billable_metrics")

    expect(response).to have_http_status(:success)
    expect(json[:billable_metrics].map { it[:lago_id] }).to include(billable_metric.id)
  end
end
