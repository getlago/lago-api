# frozen_string_literal: true

require "rails_helper"

RSpec.describe Public::V1::PermissionsController do
  describe "GET /public/v1/permissions" do
    it "returns the default role table" do
      get "/public/v1/permissions"

      expect(response).to have_http_status(:success)
      expect(JSON.parse(response.body)["permissions"]).to eq(Permission::DEFAULT_ROLE_TABLE)
    end
  end
end
