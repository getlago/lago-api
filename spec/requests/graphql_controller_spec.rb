# frozen_string_literal: true

require "rails_helper"

RSpec.describe GraphqlController do
  describe "POST /graphql" do
    before do
      allow(CurrentContext).to receive(:source=)
      allow(CurrentContext).to receive(:api_key_id=)
    end

    context "when logging in" do
      let(:membership) { create(:membership) }
      let(:user) { membership.user }

      let(:mutation) do
        <<~GQL
          mutation($input: LoginUserInput!) {
            loginUser(input: $input) {
              token
              user {
                id
                organizations { id name }
              }
            }
          }
        GQL
      end

      before do
        post "/graphql",
          params: {
            query: mutation,
            variables: {
              input: {
                email: user.email,
                password: "ILoveLago"
              }
            }
          }
      end

      it "returns GraphQL response" do
        expect(response.status).to be(200)
        expect(CurrentContext).to have_received(:source=).with("graphql")
        expect(CurrentContext).to have_received(:api_key_id=).with(nil)

        json = JSON.parse(response.body)
        expect(json["data"]["loginUser"]["token"]).to be_present
        expect(json["data"]["loginUser"]["user"]["id"]).to eq(user.id)
        expect(json["data"]["loginUser"]["user"]["organizations"].first["id"]).to eq(membership.organization_id)
      end

      context "when membership is revoked" do
        let(:membership) { create(:membership, :revoked) }

        it "returns an error" do
          expect(response.status).to be(200)

          json = JSON.parse(response.body)
          error = json["errors"].first
          expect(error["extensions"]["code"]).to eq("unprocessable_entity")
          expect(error.dig("extensions", "details", "base")).to eq ["incorrect_login_or_password"]
          expect(error["extensions"]["status"]).to eq(422)
        end
      end
    end

    context "with JWT token" do
      let(:user) { create(:user) }
      let(:query) do
        <<~GRAPHQL
          query {
            currentUser {
              id
              premium
              memberships {
                status
                organization {
                  id
                }
              }
            }
          }
        GRAPHQL
      end

      let(:token) do
        Utils::AuthToken.encode(user:, login_method: Organizations::AuthenticationMethods::EMAIL_PASSWORD)
      end

      it "retrieves the current user" do
        post "/graphql",
          headers: {
            "Authorization" => "Bearer #{token}"
          },
          params: {
            query:
          }

        expect(response.status).to be(200)
        expect(json[:data][:currentUser][:id]).to eq user.id
        expect(json[:data][:currentUser][:memberships]).to be_empty
      end

      context "when organization id header is set" do
        context "when user is not part of organization" do
          it "returns no membership" do
            post "/graphql",
              headers: {
                "Authorization" => "Bearer #{token}",
                "x-lago-organization" => SecureRandom.uuid
              },
              params: {
                query:
              }

            expect(json[:data][:currentUser][:memberships]).to be_empty
          end
        end

        context "when user is part of organization" do
          let(:admin_role) { create(:role, :admin) }
          let(:membership) { create(:membership, user:) }
          let(:organization) { membership.organization }

          before { create(:membership_role, membership:, role: admin_role) }

          it "returns the membership" do
            post "/graphql",
              headers: {
                "Authorization" => "Bearer #{token}",
                "x-lago-organization" => organization.id
              },
              params: {
                query:
              }

            expect(json[:data][:currentUser][:memberships].sole[:organization][:id]).to eq organization.id
          end
        end

        context "when membership is revoked" do
          let(:membership) { create(:membership, :revoked, user:) }
          let(:organization) { membership.organization }

          it "returns the membership" do
            post "/graphql",
              headers: {
                "Authorization" => "Bearer #{token}",
                "x-lago-organization" => organization.id
              },
              params: {
                query:
              }

            expect(json[:data][:currentUser][:memberships]).to be_empty
          end
        end
      end

      context "when token is near expiration" do
        it "renews the token" do
          post(
            "/graphql",
            headers: {
              "Authorization" => "Bearer #{JWT.encode({sub: user.id, exp: 30.minutes.from_now.to_i}, ENV["SECRET_KEY_BASE"], "HS256")}"
            },
            params: {
              query:
            }
          )

          expect(response.status).to be(200)
          expect(response.headers["x-lago-token"]).to be_present
        end
      end
    end

    context "with an SSO session" do
      let(:okta) { Organizations::AuthenticationMethods::OKTA }
      let(:user) { create(:user) }
      let(:sso_organization) { create(:organization, authentication_methods: [okta]) }
      let(:other_organization) { create(:organization, authentication_methods: %w[email_password okta]) }
      let(:sso_integration) { create(:okta_integration, organization: sso_organization, domain: "sso.test", host: "sso.okta.com") }
      let(:token) { Utils::AuthToken.encode(user:, login_method: okta, sso_organization_id: sso_organization.id, sso_issuer: sso_integration.sso_issuer) }
      let(:query) do
        <<~GRAPHQL
          query {
            organization { id apiKey accessibleByCurrentSession }
          }
        GRAPHQL
      end

      before do
        create(:membership, user:, organization: sso_organization, roles: [:admin])
        create(:membership, user:, organization: other_organization, roles: [:admin])
      end

      def query_organization(organization)
        post "/graphql",
          headers: {"Authorization" => "Bearer #{token}", "x-lago-organization" => organization.id},
          params: {query:}
      end

      it "opens the organization whose integration authenticated the user" do
        query_organization(sso_organization)

        expect(json[:errors]).to be_nil
        expect(json[:data][:organization][:id]).to eq(sso_organization.id)
        expect(json[:data][:organization][:accessibleByCurrentSession]).to be(true)
      end

      it "refuses another organization that allows Okta through another identity provider" do
        create(:okta_integration, organization: other_organization, domain: "other.test", host: "other.okta.com")

        query_organization(other_organization)

        expect(json[:data][:organization]).to be_nil
        expect(json[:errors].first[:extensions][:code]).to eq("forbidden")
      end

      it "refuses another organization that allows Okta without an Okta integration" do
        query_organization(other_organization)

        expect(json[:errors].first[:extensions][:code]).to eq("forbidden")
      end

      it "opens another organization whose integration uses the same identity provider" do
        create(:okta_integration, organization: other_organization, domain: "other.test", host: "SSO.okta.com")

        query_organization(other_organization)

        expect(json[:errors]).to be_nil
        expect(json[:data][:organization][:id]).to eq(other_organization.id)
      end

      context "when the token has no SSO claims" do
        let(:token) { Utils::AuthToken.encode(user:, login_method: okta) }

        it "refuses every organization" do
          query_organization(sso_organization)

          expect(json[:errors].first[:extensions][:code]).to eq("forbidden")
        end
      end
    end

    context "with a session whose login method the organization does not allow" do
      let(:membership) { create(:membership, roles: [:admin]) }
      let(:token) { Utils::AuthToken.encode(user: membership.user, login_method: Organizations::AuthenticationMethods::OKTA) }

      it "refuses the organization" do
        post "/graphql",
          headers: {"Authorization" => "Bearer #{token}", "x-lago-organization" => membership.organization_id},
          params: {query: "query { organization { id } }"}

        expect(json[:errors].first[:extensions][:code]).to eq("forbidden")
      end
    end

    context "with customer portal token" do
      let(:customer) { create(:customer) }
      let(:query) do
        <<~GQL
          query {
            customerPortalInvoices(limit: 5) {
              collection { id }
              metadata { currentPage, totalCount }
            }
          }
        GQL
      end
      let(:token) do
        ActiveSupport::MessageVerifier.new(ENV["SECRET_KEY_BASE"]).generate(customer.id, expires_in: 12.hours)
      end

      it "retrieves the correct end user and returns success status code" do
        post(
          "/graphql",
          headers: {
            "customer-portal-token" => token
          },
          params: {
            query:
          }
        )

        expect(response.status).to be(200)
      end
    end

    context "with null bytes in the variables" do
      let(:membership) { create(:membership, roles: [:admin]) }
      let(:token) { Utils::AuthToken.encode(user: membership.user, login_method: Organizations::AuthenticationMethods::EMAIL_PASSWORD) }
      let(:query) do
        <<~GRAPHQL
          query($searchTerm: String) {
            customers(searchTerm: $searchTerm) { collection { id } }
          }
        GRAPHQL
      end

      before { create(:customer, organization: membership.organization, name: "ab") }

      it "strips them instead of returning a 500" do
        post "/graphql",
          headers: {
            "Authorization" => "Bearer #{token}",
            "x-lago-organization" => membership.organization_id,
            "Content-Type" => "application/json"
          },
          params: {query:, variables: {searchTerm: "a\u0000b"}}.to_json

        expect(response.status).to be(200)
        expect(json[:errors]).to be_nil
        expect(json[:data][:customers][:collection].count).to eq(1)
      end
    end

    context "with a null byte escape in an inline string literal" do
      let(:membership) { create(:membership, roles: [:admin]) }
      let(:token) { Utils::AuthToken.encode(user: membership.user, login_method: Organizations::AuthenticationMethods::EMAIL_PASSWORD) }

      before { create(:customer, organization: membership.organization, name: "ab") }

      def search(term_literal)
        post "/graphql",
          headers: {
            "Authorization" => "Bearer #{token}",
            "x-lago-organization" => membership.organization_id,
            "Content-Type" => "application/json"
          },
          params: {query: "query { customers(searchTerm: \"#{term_literal}\") { collection { id } } }"}.to_json
      end

      it "strips the decoded null byte instead of returning a 500" do
        search('a\\u0000b')

        expect(response.status).to be(200)
        expect(json[:errors]).to be_nil
        expect(json[:data][:customers][:collection].count).to eq(1)
      end

      it "keeps an escaped backslash followed by u0000 as text" do
        search('a\\\\u0000')

        expect(response.status).to be(200)
        expect(json[:errors]).to be_nil
      end
    end

    context "with a null byte escape inside an inline JSON argument", :premium do
      let(:membership) { create(:membership, roles: [:admin]) }
      let(:token) { Utils::AuthToken.encode(user: membership.user, login_method: Organizations::AuthenticationMethods::EMAIL_PASSWORD) }
      let(:customer) { create(:customer, organization: membership.organization) }
      let(:add_on) { create(:add_on, organization: membership.organization) }

      before { membership.organization.enable_feature_flag!(:order_forms) }

      it "strips it instead of returning a 500" do
        mutation = <<~GQL
          mutation {
            createQuote(input: {
              customerId: "#{customer.id}",
              orderType: one_off,
              content: "Test content",
              billingItems: {addOns: [{
                id: "#{add_on.id}",
                localId: "a\\u0000b",
                type: "add_on",
                payload: {code: "#{add_on.code}", units: 1, unitAmountCents: 10000, totalAmountCents: 10000}
              }]}
            }) {
              currentVersion { billingItems }
            }
          }
        GQL

        post "/graphql",
          headers: {
            "Authorization" => "Bearer #{token}",
            "x-lago-organization" => membership.organization_id,
            "Content-Type" => "application/json"
          },
          params: {query: mutation}.to_json

        expect(response.status).to be(200)
        expect(json[:errors]).to be_nil
        expect(json[:data][:createQuote][:currentVersion][:billingItems][:addOns].first[:localId]).to eq("ab")
      end
    end

    context "with query length validation" do
      let(:user) { create(:user) }
      let(:token) do
        Utils::AuthToken.encode(user:)
      end

      it "rejects queries that exceed maximum length" do
        long_query = "query { " + "a" * (GraphqlController::MAX_QUERY_LENGTH + 1) + " }"

        post "/graphql",
          headers: {
            "Authorization" => "Bearer #{token}"
          },
          params: {
            query: long_query
          }

        expect(response.status).to be(200)

        json = JSON.parse(response.body)
        expect(json["errors"]).to be_present
        expect(json["errors"].first["message"]).to include("Max query length is 15000")
        expect(json["errors"].first["extensions"]["code"]).to eq("query_is_too_large")
        expect(json["errors"].first["extensions"]["status"]).to eq(413)
      end

      it "accepts queries within maximum length" do
        query = <<~GRAPHQL
          query {
            currentUser {
              id
              premium
              memberships {
                status
                organization {
                  id
                }
              }
            }
          }
        GRAPHQL

        post "/graphql",
          headers: {
            "Authorization" => "Bearer #{token}"
          },
          params: {
            query:
          }

        expect(response.status).to be(200)

        expect(json["errors"]).not_to be_present
      end
    end
  end
end
