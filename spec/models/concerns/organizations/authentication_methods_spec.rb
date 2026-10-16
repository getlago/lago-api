# frozen_string_literal: true

require "rails_helper"

RSpec.describe Organizations::AuthenticationMethods do
  describe "authentication_methods" do
    let_it_be(:organization, refind: true) { create_default(:organization) }

    before do
      organization
    end

    it "creates with default values" do
      expect(organization.authentication_methods.count).to eq(Organization::FREE_AUTHENTICATION_METHODS.count)
      expect(organization.authentication_methods).to eq(Organization::FREE_AUTHENTICATION_METHODS)
    end

    Organization::FREE_AUTHENTICATION_METHODS.each do |auth|
      context "when FREE AUTHENTICATION METHOD #{auth}" do
        it "is enabled by default" do
          expect(organization.authentication_methods).to include(auth)
        end

        it "can be disabled" do
          expect(organization.send(:"disable_#{auth}_authentication!")).to be_truthy
          expect(organization.send(:"#{auth}_authentication_enabled?")).to be_falsey
        end

        it "can be enabled" do
          expect(organization.send(:"enable_#{auth}_authentication!")).to be_truthy
          expect(organization.send(:"#{auth}_authentication_enabled?")).to be_truthy
        end
      end
    end

    Organization::PREMIUM_AUTHENTICATION_METHODS.each do |auth|
      context "when PREMIUM AUTHENTICATION METHOD #{auth}" do
        it "is not enabled by default" do
          expect(organization.authentication_methods).not_to include(auth)
        end

        context "with free organization" do
          it "cant be enabled" do
            expect(organization.send(:"enable_#{auth}_authentication!")).to be_falsey
            expect(organization.send(:"#{auth}_authentication_enabled?")).to be_falsey
          end
        end

        context "with premium organization", :premium do
          before do
            organization.premium_integrations << auth
          end

          it "can be enabled" do
            expect(organization.send(:"enable_#{auth}_authentication!")).to be_truthy
            expect(organization.send(:"#{auth}_authentication_enabled?")).to be_truthy
          end

          it "can be disabled" do
            organization.send(:"enable_#{auth}_authentication!")
            expect(organization.send(:"disable_#{auth}_authentication!")).to be_truthy
            expect(organization.send(:"#{auth}_authentication_enabled?")).to be_falsey
          end
        end
      end
    end

    context "when disabling authentication methods" do
      it "cant disable all" do
        expect do
          organization.authentication_methods.dup.each do |auth|
            organization.send(:"disable_#{auth}_authentication!")
          end
        end.to raise_error(ActiveRecord::RecordInvalid)
      end
    end

    context "when invalid auth" do
      it "cant save" do
        expect do
          organization.authentication_methods = ["strange"]
          organization.save!
        end.to raise_error(ActiveRecord::RecordInvalid)
      end
    end
  end

  describe "#accessible_by_session?" do
    let(:organization) { create(:organization, authentication_methods: %w[email_password okta]) }
    let(:okta) { Organizations::AuthenticationMethods::OKTA }

    it "refuses a session whose login method the organization does not allow" do
      expect(organization.accessible_by_session?(login_method: "google_oauth")).to be(false)
      expect(organization.accessible_by_session?(login_method: nil)).to be(false)
    end

    it "accepts a non SSO session whose login method the organization allows" do
      expect(organization.accessible_by_session?(login_method: "email_password")).to be(true)
    end

    context "with an SSO session" do
      before { create(:okta_integration, organization:, domain: "acme.test", host: "acme.okta.com") }

      it "accepts the organization whose integration authenticated the user" do
        expect(organization.accessible_by_session?(login_method: okta, sso_organization_id: organization.id, sso_issuer: "evil.test")).to be(true)
      end

      it "accepts an organization whose integration has the same issuer" do
        expect(organization.accessible_by_session?(login_method: okta, sso_organization_id: SecureRandom.uuid, sso_issuer: "acme.okta.com")).to be(true)
      end

      it "refuses an organization whose integration has another issuer" do
        expect(organization.accessible_by_session?(login_method: okta, sso_organization_id: SecureRandom.uuid, sso_issuer: "evil.test")).to be(false)
      end

      it "refuses a session without SSO claims" do
        expect(organization.accessible_by_session?(login_method: okta)).to be(false)
      end
    end

    context "when the organization allows Okta without an Okta integration" do
      it "refuses a session from another organization" do
        expect(organization.accessible_by_session?(login_method: okta, sso_organization_id: SecureRandom.uuid, sso_issuer: "acme.okta.com")).to be(false)
      end
    end
  end
end
