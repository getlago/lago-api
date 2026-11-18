# frozen_string_literal: true

require "rails_helper"

describe Api::RequiresCatalogWallets do
  include ApiHelper

  # rubocop:disable RSpec/DescribedClass
  controller(ApplicationController) do
    include Api::V2Errors
    include Api::RequiresCatalogWallets

    attr_reader :current_organization

    def index
      render json: {ok: true}
    end
  end
  # rubocop:enable RSpec/DescribedClass

  let(:organization) { create(:organization, feature_flags:) }
  let(:feature_flags) { ["product_catalog"] }

  before { allow(controller).to receive(:current_organization).and_return(organization) }

  context "when the organization is not on catalog wallets" do
    it "returns a forbidden error" do
      get :index

      expect(response).to have_http_status(:forbidden)
      expect(json).to eq(code: "feature_unavailable", details: [])
    end
  end

  context "when the organization is on catalog wallets" do
    let(:feature_flags) { ["product_catalog", "catalog_wallets"] }

    it "allows the request" do
      get :index

      expect(response).to have_http_status(:success)
      expect(json[:ok]).to be(true)
    end
  end
end
