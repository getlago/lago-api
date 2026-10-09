# frozen_string_literal: true

RSpec.shared_examples "a CS admin operation" do
  let(:current_user) { admin_user }

  context "without a premium license" do
    it "rejects the request" do
      expect_graphql_error(result: response, message: "unauthorized")
    end
  end

  context "with a premium license", :premium do
    context "without a signed-in user" do
      let(:current_user) { nil }

      it "rejects the request" do
        expect_graphql_error(result: response, message: "unauthorized")
      end
    end

    context "with a CS admin outside Lago" do
      let(:current_user) { create(:user, email: "cs@external.test", cs_admin: true) }

      it "rejects the request" do
        expect_graphql_error(result: response, message: "unauthorized")
      end
    end

    context "with a Lago user without admin access" do
      let(:current_user) { create(:user, email: "sales@getlago.com", cs_admin: false) }

      it "rejects the request" do
        expect_graphql_error(result: response, message: "unauthorized")
      end
    end
  end
end
