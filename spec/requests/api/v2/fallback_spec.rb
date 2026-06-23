# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API v2 fallback to v1" do
  let(:organization) { create(:organization) }

  it "serves a v1-backed resource under /api/v2" do
    plan = create(:plan, organization:)

    get_with_token(organization, "/api/v2/plans")

    expect(response).to have_http_status(:success)
    expect(json[:plans].map { it[:lago_id] }).to include(plan.id)
  end
end
