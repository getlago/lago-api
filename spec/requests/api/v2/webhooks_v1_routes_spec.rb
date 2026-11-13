# frozen_string_literal: true

require "rails_helper"

# v1 controllers serve these routes, so with v1 timestamps.
RSpec.describe "API v2 webhook routes left to v1", v2_timestamps: false do
  let(:organization) { create(:organization) }

  %w[/webhooks/public_key /webhooks/json_public_key].each do |path|
    it "answers 404 to GET #{path} on v2" do
      get_with_token(organization, "/api/v2#{path}")

      expect(response).to be_not_found_error("resource")
    end

    it "keeps serving GET #{path} on v1" do
      get_with_token(organization, "/api/v1#{path}")

      expect(response).to have_http_status(:success)
    end
  end
end
