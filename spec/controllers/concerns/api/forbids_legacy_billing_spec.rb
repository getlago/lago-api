# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::ForbidsLegacyBilling do
  include ApiHelper

  # rubocop:disable RSpec/DescribedClass
  controller(ApplicationController) do
    include ApiErrors
    include Api::ForbidsLegacyBilling

    attr_reader :current_organization

    def create
      render json: {ok: true}
    end

    def update
      render json: {ok: true}
    end

    def destroy
      render json: {ok: true}
    end

    def index
      render json: {ok: true}
    end
  end
  # rubocop:enable RSpec/DescribedClass

  let(:organization) { create(:organization, feature_flags:) }
  let(:feature_flags) { [] }

  before { allow(controller).to receive(:current_organization).and_return(organization) }

  context "when the organization is on the product catalog", :premium do
    let(:feature_flags) { ["product_catalog"] }

    it "blocks writes" do
      post :create

      expect(response).to have_http_status(:forbidden)
      expect(json[:code]).to eq("legacy_billing_disabled")
    end

    it "still allows reads" do
      get :index

      expect(response).to have_http_status(:success)
    end
  end

  context "when the organization is not on the product catalog" do
    it "allows writes" do
      post :create

      expect(response).to have_http_status(:success)
    end
  end

  describe "on a controller defining only a subset of the write actions" do
    # rubocop:disable RSpec/DescribedClass
    controller(ApplicationController) do
      include ApiErrors
      include Api::ForbidsLegacyBilling

      attr_reader :current_organization

      def index
        render json: {ok: true}
      end

      def update
        render json: {ok: true}
      end
    end
    # rubocop:enable RSpec/DescribedClass

    let(:feature_flags) { ["product_catalog"] }

    it "serves reads without raising and still blocks the defined writes" do
      routes.draw do
        get "index" => "anonymous#index"
        put "update" => "anonymous#update"
      end

      get :index
      expect(response).to have_http_status(:success)

      put :update, params: {id: "x"}
      expect(response).to have_http_status(:forbidden)
      expect(json[:code]).to eq("legacy_billing_disabled")
    end
  end
end
