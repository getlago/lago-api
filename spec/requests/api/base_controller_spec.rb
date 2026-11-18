# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::BaseController, type: :controller do
  let_it_be(:organization) { create_default(:organization) }
  # Api::BaseController is abstract: the v1 base controller adds the renderers its callbacks call.
  controller(Api::V1::BaseController) do
    def index
      render nothing: true
    end

    def create
      params.require(:input).permit(:value)
      render nothing: true
    end

    def track_api_key_usage?
      action_name.to_sym != :create
    end
  end

  let(:api_key) { create(:api_key) }

  before do
    allow(CurrentContext).to receive(:source=)
    allow(CurrentContext).to receive(:api_key_id=)
  end

  it { expect(described_class).to be_abstract }

  it "sets the context source to api" do
    request.headers["Authorization"] = "Bearer #{api_key.value}"

    get :index

    expect(CurrentContext).to have_received(:source=).with("api")
    expect(CurrentContext).to have_received(:api_key_id=).with(api_key.id)
  end

  describe "#authenticate" do
    before do
      request.headers["Authorization"] = "Bearer #{api_key.value}"
      get :index
    end

    context "with valid authorization header" do
      let(:api_key) { [create(:api_key), create(:api_key, :expiring)].sample }

      it "returns success response" do
        expect(response).to have_http_status(:success)
      end
    end

    context "with invalid authentication header" do
      let(:api_key) { create(:api_key, :expired) }

      it "returns an authentication error" do
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe "#refuse_inactive_organization" do
    include_context "with self-serve enabled"

    let(:waiting_organization) { create(:organization, :self_serve, activation_status: "pending_payment_method") }
    let(:api_key) { create(:api_key, organization: waiting_organization) }

    before { request.headers["Authorization"] = "Bearer #{api_key.value}" }

    it "refuses a request for an organization waiting for a payment method" do
      get :index

      expect(response).to have_http_status(:forbidden)
      expect(JSON.parse(response.body)).to eq("status" => 403, "error" => "Forbidden", "code" => "organization_inactive")
    end

    context "with self-serve disabled" do
      let(:self_serve_env) { super().merge("LAGO_SELF_SERVE_ENABLED" => "false") }

      it "lets the request through, as the organization counts as active" do
        get :index

        expect(response).to have_http_status(:success)
      end
    end

    context "with a cached copy of the organization from before its activation" do
      let(:stale_organization) { Organization.find(waiting_organization.id) }

      before do
        stale_organization
        waiting_organization.update!(activation_status: "active")
        allow(ApiKeys::CacheService).to receive(:call).and_return([api_key, stale_organization])
      end

      it "reads the organization again and lets the request through" do
        get :index

        expect(response).to have_http_status(:success)
      end
    end

    context "with an active organization" do
      let(:api_key) { create(:api_key) }

      it "lets the request through" do
        get :index

        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "#track_api_key_usage", cache: :memory do
    let(:api_key) { create(:api_key) }
    let(:cache_key) { "api_key_last_used_#{api_key.id}" }

    before do
      request.headers["Authorization"] = "Bearer #{api_key.value}"
      freeze_time
    end

    context "when accessed trackable endpoint" do
      subject { get :index }

      it "caches when API key was last used" do
        expect { subject }.to change { Rails.cache.read(cache_key) }.to Time.current.iso8601
      end
    end

    context "when accessed non-trackable endpoint" do
      subject { get :create }

      it "does not cache when API key was last used" do
        expect { subject }.not_to change { Rails.cache.read(cache_key) }.from nil
      end
    end
  end

  it "catches the missing parameters error" do
    request.headers["Authorization"] = "Bearer #{api_key.value}"

    post :create

    expect(response).to have_http_status(:bad_request)

    json = JSON.parse(response.body, symbolize_names: true)
    expect(json[:status]).to eq(400)
    expect(json[:error]).to eq("BadRequest: param is missing or the value is empty or invalid: input")
  end
end
