# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agents::ClaimsController, :premium, cache: :memory do
  let(:organization) { create(:organization, premium_integrations: %w[agent_storefront]) }
  let(:storefront) { create(:agent_storefront_integration, organization:) }
  let(:plan) { create(:plan, organization:, amount_cents: 0, amount_currency: "USD") }
  let(:base) { "/agents/v1/#{storefront.id}" }
  let(:key) { OpenSSL::PKey.generate_key("ED25519") }
  let(:public_key) { Base64.urlsafe_encode64(key.raw_public_key, padding: false) }

  before { storefront.update!(plans: [{plan_code: plan.code}]) }

  def token(purpose, path, scope: nil)
    post("#{base}/auth/challenges", params: {public_key:, purpose:, scope:}.compact, as: :json)
    signature = Base64.urlsafe_encode64(key.sign(nil, Base64.urlsafe_decode64(json[:message])), padding: false)
    post("#{base}/#{path}", params: {challenge_id: json[:challenge_id], signature:}, as: :json)
    json[:access_token]
  end

  def mailed_code
    digest = Agents::Claim.sole.verification_code_hash
    CGI.unescapeHTML(ActionMailer::Base.deliveries.last.body.encoded).scan(/\b\d{6}\b/).find { Agents::Claim.digest(it) == digest }
  end

  it "takes an agent from a claim code to a verified owner e-mail" do
    api_token = token("signup", "signup")
    headers = {"Authorization" => "Bearer #{token("authenticate", "auth/token", scope: "billing")}"}

    post("#{base}/claims/codes", headers:)
    expect(response).to have_http_status(:unprocessable_content)
    expect(json[:error_details]).to eq(base: ["enrollment_required"])

    post("#{base}/billing/enroll", params: {plan_code: plan.code}, headers:, as: :json)

    post("#{base}/claims/codes", headers:)
    expect(response).to have_http_status(:ok)
    expect(json).to include(claim_url: "#{Rails.application.config.lago_front_url}/agent-claim/#{storefront.id}", status: "unclaimed")
    code = json[:claim_code]
    expect(code).to match(/\A[A-Z2-9]{4}-[A-Z2-9]{4}\z/)

    get("#{base}/claims", headers:)
    expect(json).to include(status: "unclaimed", claimed_at: nil)

    perform_enqueued_jobs do
      post("#{base}/claims/start", params: {claim_code: code.downcase, email: "owner@example.com"}, as: :json)
    end
    expect(response).to have_http_status(:ok)
    expect(json).to eq(status: "pending", expires_in: 600)
    expect(ActionMailer::Base.deliveries.last.to).to eq(["owner@example.com"])

    get("#{base}/claims", headers:)
    expect(json).to include(status: "pending")

    post("#{base}/claims/verify", params: {claim_code: code, verification_code: "000000"}, as: :json)
    expect(response).to have_http_status(:unprocessable_content)
    expect(json[:error_details]).to eq(verification_code: ["invalid_verification_code"])

    post("#{base}/claims/verify", params: {claim_code: code, verification_code: mailed_code}, as: :json)
    expect(response).to have_http_status(:ok)
    expect(json).to include(status: "claimed")
    expect(json[:claimed_at]).to be_present

    get("#{base}/claims", headers:)
    expect(json).to include(status: "claimed", claimed_at: json[:claimed_at])
    expect(organization.customers.sole.email).to eq("owner@example.com")

    post("#{base}/claims/codes", headers:)
    expect(json[:error_details]).to eq(base: ["registration_already_claimed"])

    post("#{base}/claims/codes", headers: {"Authorization" => "Bearer #{api_token}"})
    expect(response).to have_http_status(:unauthorized)
    expect(json[:error]).to eq("invalid_token")
  end

  it "lets the owner claim the agent again once the merchant deleted its customer" do
    token("signup", "signup")
    headers = {"Authorization" => "Bearer #{token("authenticate", "auth/token", scope: "billing")}"}
    post("#{base}/billing/enroll", params: {plan_code: plan.code}, headers:, as: :json)
    registration = storefront.agent_registrations.sole
    create(:agent_claim, :verified, registration:)
    registration.customer.update!(email: "owner@example.com")

    Customers::DestroyService.call!(customer: registration.customer)

    get("#{base}/claims", headers:)
    expect(json).to include(status: "unclaimed", claimed_at: nil)

    post("#{base}/billing/enroll", params: {plan_code: plan.code}, headers:, as: :json)
    expect(response).to have_http_status(:ok)
    expect(registration.customer.email).to be_nil

    post("#{base}/claims/codes", headers:)
    expect(response).to have_http_status(:ok)
    expect(json).to include(status: "unclaimed")
    expect(registration.claims.pluck(:status)).to eq(["issued"])
  end

  it "filters the codes from the logged parameters" do
    post("#{base}/claims/start", params: {claim_code: "ABCD-2345", email: "owner@example.com"}, as: :json)
    expect(request.filtered_parameters["claim_code"]).to eq("[FILTERED]")

    post("#{base}/claims/verify", params: {claim_code: "ABCD-2345", verification_code: "123456"}, as: :json)
    expect(request.filtered_parameters["verification_code"]).to eq("[FILTERED]")
  end

  describe "throttles on the owner's calls" do
    let(:claim) { create(:agent_claim, registration: create(:agent_registration, storefront:), code: "ABCD2345") }

    before do
      claim
      Auth::AttemptsThrottle.store = ActiveSupport::Cache::MemoryStore.new
    end

    it "mails a code three times per claim code, then refuses" do
      3.times do |i|
        post("#{base}/claims/start", params: {claim_code: "ABCD2345", email: "owner#{i}@example.com"}, as: :json)
        expect(response).to have_http_status(:ok)
      end

      post("#{base}/claims/start", params: {claim_code: "ABCD2345", email: "owner3@example.com"}, as: :json)
      expect(response).to have_http_status(:too_many_requests)
      expect(json[:code]).to eq("too_many_requests")
    end

    it "mails a mailbox three times an hour, whatever the codes" do
      create(:agent_claim, registration: create(:agent_registration, storefront:), code: "EFGH2345")
      %w[ABCD2345 EFGH2345 ABCD2345].each do |code|
        post("#{base}/claims/start", params: {claim_code: code, email: "owner@example.com"}, as: :json)
        expect(response).to have_http_status(:ok)
      end

      post("#{base}/claims/start", params: {claim_code: "EFGH2345", email: "owner@example.com"}, as: :json)
      expect(response).to have_http_status(:too_many_requests)
      expect(json[:code]).to eq("too_many_requests")
    end

    it "takes five wrong verification codes per claim code, then refuses" do
      claim.update!(status: :started, email: "owner@example.com", verification_code_hash: Agents::Claim.digest("123456"), verification_expires_at: 10.minutes.from_now)

      5.times do
        post("#{base}/claims/verify", params: {claim_code: "ABCD2345", verification_code: "000000"}, as: :json)
        expect(response).to have_http_status(:unprocessable_content)
      end

      post("#{base}/claims/verify", params: {claim_code: "ABCD2345", verification_code: "123456"}, as: :json)
      expect(response).to have_http_status(:too_many_requests)
      expect(claim.reload).to be_started
    end
  end

  context "when the storefront does not exist" do
    it "answers 404 on the owner's calls" do
      post("/agents/v1/#{SecureRandom.uuid}/claims/start", params: {claim_code: "ABCD2345", email: "owner@example.com"}, as: :json)

      expect(response).to have_http_status(:not_found)
      expect(json[:code]).to eq("agent_storefront_not_found")
    end
  end
end
