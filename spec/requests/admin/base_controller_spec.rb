# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::BaseController, type: [:controller, :admin] do
  controller do
    def index
      render nothing: true
    end
  end

  describe "authenticate" do
    context "with a valid admin api key" do
      before { request.headers["X-Admin-API-Key"] = AdminHelper::ADMIN_API_KEY }

      it "authenticates the request" do
        get :index

        expect(response).to have_http_status(:success)
      end
    end

    context "without authentication header" do
      it "returns an authentication error" do
        get :index

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "with an invalid admin api key" do
      before { request.headers["X-Admin-API-Key"] = "wrong" }

      it "returns an authentication error" do
        get :index

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "with a bearer token" do
      before { request.headers["Authorization"] = "Bearer 123456" }

      it "returns an authentication error" do
        get :index

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when ADMIN_API_KEY is not configured" do
      before do
        allow(ENV).to receive(:[]).with("ADMIN_API_KEY").and_return(nil)
        request.headers["X-Admin-API-Key"] = ""
      end

      it "returns an authentication error" do
        get :index

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
