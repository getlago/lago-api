# frozen_string_literal: true

require "rails_helper"

RSpec.describe Graphql::ApiController, type: :request do
  describe "POST /api_graphql" do
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

    it "returns GraphQL response" do
      post "/api/graphql",
        params: {
          query: mutation,
          variables: {
            input: {
              email: user.email,
              password: "ILoveLago"
            }
          }
        }

      expect(response.status).to be(200)
      expect(CurrentContext.source).to eq "graphql"

      json = JSON.parse(response.body)
      expect(json["data"]["loginUser"]["token"]).to be_present
      expect(json["data"]["loginUser"]["user"]["id"]).to eq(user.id)
      expect(json["data"]["loginUser"]["user"]["organizations"].first["id"]).to eq(membership.organization_id)
    end

    context "with JWT token" do
      let(:token) do
        UsersService.new.new_token(user).token
      end
      let(:expired_token) do
        JWT.encode(
          {
            sub: user.id,
            exp: Time.now.to_i
          },
          ENV["SECRET_KEY_BASE"],
          "HS256"
        )
      end

      it "retrieves the current user and refreshes the token" do
        post "/api/graphql",
          headers: {
            "Authorization" => "Bearer #{token}"
          },
          params: {
            query: mutation,
            variables: {
              input: {
                email: user.email,
                password: "ILoveLago"
              }
            }
          }

        expect(response.status).to be(200)
        expect(response.headers["x-lago-token"]).to be_present
      end

      it "retrieves the current organization" do
        post "/api/graphql",
          headers: {
            "Authorization" => "Bearer #{token}",
            "x-lago-organization" => membership.organization
          },
          params: {
            query: mutation,
            variables: {
              input: {
                email: user.email,
                password: "ILoveLago"
              }
            }
          }

        expect(response.status).to be(200)
        expect(response.headers["x-lago-token"]).to be_present
      end

      it "handles the token expiration" do
        expired_token
        sleep 1 # Ensure token is expired

        post(
          "/api/graphql",
          headers: {
            "Authorization" => "Bearer #{expired_token}"
          },
          params: {
            query: mutation,
            variables: {
              input: {
                email: user.email,
                password: "ILoveLago"
              }
            }
          }
        )

        expect(response.status).to be(200)

        json = JSON.parse(response.body)
        expect(json["errors"]).to be_present
        expect(json["errors"].first["message"]).to eq("expired_jwt_token")
        expect(json["errors"].first["extensions"]["code"]).to eq("expired_jwt_token")
        expect(json["errors"].first["extensions"]["status"]).to eq(401)
      end
    end
  end
end
