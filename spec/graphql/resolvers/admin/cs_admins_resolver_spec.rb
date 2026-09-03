# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::Admin::CsAdminsResolver do
  let(:query) do
    <<~GQL
      query {
        adminCsAdmins { id email csAdmin }
      }
    GQL
  end

  let(:admin_user) { create(:user, email: "cs@getlago.com", cs_admin: true) }
  let(:regular_user) { create(:user, email: "user@acme.test") }

  before do
    create(:user, email: "andy@getlago.com", cs_admin: true)
  end

  it "returns the CS admins ordered by email", :premium do
    result = execute_graphql(current_user: admin_user, query:)

    cs_admins = result["data"]["adminCsAdmins"]
    expect(cs_admins.map { |user| user["email"] }).to eq(["andy@getlago.com", "cs@getlago.com"])
    expect(cs_admins.map { |user| user["csAdmin"] }.uniq).to eq([true])
  end

  it "excludes users who are not CS admins", :premium do
    result = execute_graphql(current_user: admin_user, query:)

    ids = result["data"]["adminCsAdmins"].map { |user| user["id"] }
    expect(ids).not_to include(regular_user.id)
  end

  context "when the license is not premium" do
    it "returns an unauthorized error" do
      result = execute_graphql(current_user: admin_user, query:)

      expect_graphql_error(result:, message: "unauthorized")
    end
  end

  context "when the user is not a CS admin" do
    it "returns an unauthorized error" do
      result = execute_graphql(current_user: regular_user, query:)

      expect_graphql_error(result:, message: "unauthorized")
    end
  end
end
