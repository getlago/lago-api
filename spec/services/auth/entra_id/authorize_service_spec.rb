# frozen_string_literal: true

require "rails_helper"

RSpec.describe Auth::EntraId::AuthorizeService do
  subject(:service) { described_class.new(email:) }

  let(:organization) { create(:organization) }
  let(:entra_id_integration) { create(:entra_id_integration) }
  let(:email) { "foo@#{entra_id_integration.domain}" }

  before { entra_id_integration }

  describe "#authorize" do
    it "returns an authorize url" do
      result = service.call

      expect(result).to be_success
      expect(result.url).to include("login.microsoftonline.com")
      expect(result.url).to include(entra_id_integration.tenant_id)
      expect(result.url).to include(entra_id_integration.client_id)
    end

    context "when domain is not configured with an integration" do
      let(:email) { "foo@bar.com" }

      it "returns a failure result" do
        result = service.call

        expect(result).not_to be_success
        expect(result.error.messages.values.flatten).to include("domain_not_configured")
      end
    end

    context "with invite token" do
      subject(:service) { described_class.new(email:, invite_token: invite.token) }

      let(:invite) { create(:invite, email:) }

      it "returns an authorize url" do
        result = service.call

        expect(result).to be_success
        expect(result.url).to include(entra_id_integration.tenant_id)
        expect(result.url).to include(entra_id_integration.client_id)
      end

      context "when invite email is different from the email" do
        let(:invite) { create(:invite, email: "foo@b.com") }

        it "returns a failure result" do
          result = service.call

          expect(result).not_to be_success
          expect(result.error.messages.values.flatten).to include("invite_email_mismatch")
        end
      end

      context "when pending invite does not exists" do
        let(:invite) { create(:invite, email:, status: :accepted) }

        it "returns a failure result" do
          result = service.call

          expect(result).not_to be_success
          expect(result.error.messages.values.flatten).to include("invite_not_found")
        end
      end
    end
  end
end
